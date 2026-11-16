#!/usr/bin/env bash
#==========================================================================
# run_all.sh - full regression and performance sweep
#
# 1. assembles every program in programs/
# 2. builds all three configurations
# 3. runs the unit tests
# 4. runs the directed hazard test on all three configurations
# 5. runs every benchmark on every configuration
# 6. compares each pipelined signature against the single-cycle reference
#    (this is the golden-model check)
# 7. writes results/perf.csv and prints the CPI/IPC comparison table
#
# Exit status is non-zero if anything failed, so this can be used as a
# pre-submission gate.
#==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build results
rm -f results/*.sig results/perf.csv results/run.log

PROGRAMS=(independent dep_chain load_use array_sum branch_mix fib vecsum64)
CONFIGS=(single stall fwd pred)
FAILURES=0

say() { printf '%s\n' "$*" | tee -a results/run.log; }
hr()  { say "------------------------------------------------------------"; }

defs_for() {
  case "$1" in
    single) echo "-DCORE_SINGLE" ;;
    stall)  echo "-DCORE_PIPE -DFWD=0 -DPRED=0" ;;
    fwd)    echo "-DCORE_PIPE -DFWD=1 -DPRED=0" ;;
    pred)   echo "-DCORE_PIPE -DFWD=1 -DPRED=1" ;;
  esac
}

RTL=(rtl/common/*.v rtl/single_cycle/*.v rtl/pipelined/*.v)

hr; say "STEP 1 - assembling programs"; hr
for p in "${PROGRAMS[@]}" hazard_suite; do
  if python3 tools/asm.py "programs/${p}.s" >> results/run.log 2>&1; then
    say "  ok   ${p}.s"
  else
    say "  FAIL ${p}.s  (see results/run.log)"
    FAILURES=$((FAILURES+1))
  fi
done

hr; say "STEP 2 - compiling"; hr
for cfg in "${CONFIGS[@]}"; do
  for tb in tb_core tb_hazards; do
    if iverilog -g2005 -Wall -Wno-timescale -I rtl/common -s "$tb" $(defs_for "$cfg") \
         -o "build/${tb}_${cfg}.out" "tb/${tb}.v" "${RTL[@]}" \
         >> results/run.log 2>&1; then
      say "  ok   ${tb} [${cfg}]"
    else
      say "  FAIL ${tb} [${cfg}]  (see results/run.log)"
      FAILURES=$((FAILURES+1))
    fi
  done
done
for tb in tb_alu tb_regfile; do
  if iverilog -g2005 -Wall -Wno-timescale -I rtl/common -s "$tb" -o "build/${tb}.out" \
       "tb/${tb}.v" rtl/common/*.v >> results/run.log 2>&1; then
    say "  ok   ${tb}"
  else
    say "  FAIL ${tb}"
    FAILURES=$((FAILURES+1))
  fi
done

hr; say "STEP 3 - unit tests"; hr
for tb in tb_alu tb_regfile; do
  OUT=$(vvp "build/${tb}.out" 2>&1)
  echo "$OUT" >> results/run.log
  if echo "$OUT" | grep -q "PASSED"; then
    say "  PASS ${tb}"
  else
    say "  FAIL ${tb}"
    echo "$OUT" | sed 's/^/        /' | tee -a results/run.log
    FAILURES=$((FAILURES+1))
  fi
done

hr; say "STEP 4 - directed hazard test"; hr
for cfg in "${CONFIGS[@]}"; do
  OUT=$(vvp "build/tb_hazards_${cfg}.out" \
            "+imem=programs/hazard_suite.imem.hex" "+cfg=${cfg}" 2>&1)
  echo "$OUT" >> results/run.log
  if echo "$OUT" | grep -q "PASSED"; then
    say "  PASS hazard_suite [${cfg}]  $(echo "$OUT" | grep -o '([0-9]* instructions in [0-9]* cycles)')"
  else
    say "  FAIL hazard_suite [${cfg}]"
    echo "$OUT" | grep -E "FAIL|TIMED" | sed 's/^/        /' | tee -a results/run.log
    FAILURES=$((FAILURES+1))
  fi
done

hr; say "STEP 5 - benchmarks"; hr
echo "program,config,instructions,cycles,stall_cycles,branches,taken_branches,mispredicts,cpi,ipc" > results/perf.csv
for p in "${PROGRAMS[@]}"; do
  for cfg in "${CONFIGS[@]}"; do
    # Plain string, not an array: macOS ships bash 3.2, where expanding an
    # empty array under "set -u" is an error.
    DMEM_ARG=""
    [ -s "programs/${p}.dmem.hex" ] && DMEM_ARG="+dmem=programs/${p}.dmem.hex"
    OUT=$(vvp "build/tb_core_${cfg}.out" \
              "+imem=programs/${p}.imem.hex" $DMEM_ARG \
              "+name=${p}" "+cfg=${cfg}" \
              "+csv=results/perf.csv" \
              "+sig=results/${p}.${cfg}.sig" 2>&1)
    echo "$OUT" >> results/run.log
    if echo "$OUT" | grep -q "TIMED OUT"; then
      say "  FAIL ${p} [${cfg}] timed out"
      FAILURES=$((FAILURES+1))
    else
      say "  ran  ${p} [${cfg}]"
    fi
  done
done

hr; say "STEP 6 - golden model check (pipelined vs single-cycle)"; hr
for p in "${PROGRAMS[@]}"; do
  for cfg in stall fwd pred; do
    if [ ! -f "results/${p}.single.sig" ] || [ ! -f "results/${p}.${cfg}.sig" ]; then
      say "  FAIL ${p} [${cfg}] signature missing"
      FAILURES=$((FAILURES+1))
    elif diff -q "results/${p}.single.sig" "results/${p}.${cfg}.sig" > /dev/null; then
      say "  MATCH ${p}: ${cfg} == single-cycle"
    else
      say "  MISMATCH ${p}: ${cfg} differs from single-cycle"
      diff "results/${p}.single.sig" "results/${p}.${cfg}.sig" \
        | head -20 | sed 's/^/        /' | tee -a results/run.log
      FAILURES=$((FAILURES+1))
    fi
  done
done

hr; say "STEP 7 - performance summary"; hr
python3 tools/perf_table.py results/perf.csv | tee -a results/run.log

hr; say "STEP 8 - pipeline traces and waveforms for the report"; hr
# Text traces make the clearest figures for the report; the VCDs are there
# for the GTKWave screenshots the deliverables ask for.
for spec in "dep_chain:stall" "dep_chain:fwd" "load_use:fwd" \
            "array_sum:fwd" "array_sum:pred" "branch_mix:fwd" \
            "branch_mix:pred" "independent:fwd"; do
  p="${spec%%:*}"; cfg="${spec##*:}"
  DMEM_ARG=""
  [ -s "programs/${p}.dmem.hex" ] && DMEM_ARG="+dmem=programs/${p}.dmem.hex"
  vvp "build/tb_core_${cfg}.out" \
      "+imem=programs/${p}.imem.hex" $DMEM_ARG \
      "+name=${p}" "+cfg=${cfg}" +trace \
      "+vcdfile=results/${p}.${cfg}.vcd" \
      > "results/trace_${p}_${cfg}.txt" 2>&1
  if [ -s "results/trace_${p}_${cfg}.txt" ]; then
    say "  wrote results/trace_${p}_${cfg}.txt and results/${p}.${cfg}.vcd"
  else
    say "  FAIL trace ${p} [${cfg}]"
    FAILURES=$((FAILURES+1))
  fi
done

hr
if [ "$FAILURES" -eq 0 ]; then
  say "ALL CHECKS PASSED"
  say "  results/perf.csv    - raw numbers"
  say "  results/perf.md     - comparison table for the report"
  say "  results/perf.md     - comparison tables for the report"
  say "  results/trace_*.txt - pipeline occupancy traces (report figures)"
  say "  results/*.vcd       - waveforms for GTKWave"
  say "  results/run.log     - full log"
  exit 0
else
  say "${FAILURES} CHECK(S) FAILED - see results/run.log"
  exit 1
fi
