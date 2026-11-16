#!/usr/bin/env bash
#==========================================================================
# synth.sh - technology-independent synthesis with Yosys
#
# Owner: Member E (infrastructure)
#
# Produces three things for the report:
#
#  A. AREA, per configuration: total cells and flip-flops.  This is the
#     figure that genuinely discriminates between the three designs - the
#     pipeline registers cost flip-flops and the forwarding network costs
#     multiplexers, and both show up directly.
#
#  B. PER-STAGE COMBINATIONAL DEPTH, in gate levels, for every stage and
#     control module synthesised standalone.  The deepest stage sets the
#     pipelined clock period; the sum of all five sets the single-cycle
#     clock period.  Their ratio is the clock-period half of the speedup
#     calculation.
#
#  C. WHOLE-CORE DEPTH, per configuration, as a cross-check on B.
#
# The two memories are blackboxed (see rtl/synth/mem_blackbox.v), because
# on an FPGA they map to block RAM and not to fabric logic.
#
# IMPORTANT CAVEAT, stated here and in the report: the generic gate
# library used below has no timing model, so "depth" counts gate levels,
# not nanoseconds, and Yosys builds the 32-bit adder as a ripple carry.
# That adder dominates every path it appears in.  Real Fmax numbers need
# Vivado (carry-chain primitives) or a standard-cell library.  Treat the
# depths as a structural comparison, not as a timing result.
#
# Usage:  ./sim/synth.sh
# Output: results/synth_<config>.txt, results/depths.txt,
#         results/synth_summary.md
#==========================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p results build

COMMON="rtl/common/alu.v rtl/common/branch_cmp.v rtl/common/control_unit.v rtl/common/imm_gen.v rtl/common/regfile.v"
PIPE="rtl/pipelined/branch_predictor.v rtl/pipelined/pc_if.v rtl/pipelined/decode_stage.v rtl/pipelined/ex_stage.v rtl/pipelined/mem_stage.v rtl/pipelined/wb_stage.v rtl/pipelined/if_id.v rtl/pipelined/id_ex.v rtl/pipelined/ex_mem.v rtl/pipelined/mem_wb.v rtl/pipelined/forwarding_unit.v rtl/pipelined/hazard_unit.v rtl/pipelined/riscv_pipeline.v"
SINGLE="rtl/single_cycle/riscv_single_cycle.v"
BB="rtl/synth/mem_blackbox.v"

MAP="abc -g AND,OR,XOR,MUX,NAND,NOR,XNOR"

: > results/depths.txt

#--------------------------------------------------------------------------
# A + C : whole core, per configuration
#--------------------------------------------------------------------------
core_run() {
  local name="$1" top="$2" chparam="$3" files="$4"
  echo "  [area+depth] ${name}  (top = ${top})"
  yosys -p "
    read_verilog -I rtl/common ${files} ${BB};
    hierarchy -check -top ${top} ${chparam};
    synth -flatten;
    ${MAP};
    opt_clean;
    stat;
    ltp -noff;
  " > "results/synth_${name}.raw" 2>&1

  # keep only the useful parts in the published log
  {
    echo "### Yosys synthesis: ${name} (top = ${top})"
    echo
    sed -n "/=== ${top} ===/,/^[0-9]*\./p" "results/synth_${name}.raw" \
      | grep -E "wires|cells|\\\$_|dmem|imem|^===" | head -40
    echo
    grep -i "Longest topological path" "results/synth_${name}.raw" | tail -1
  } > "results/synth_${name}.txt"

  local depth
  depth=$(grep -i "Longest topological path" "results/synth_${name}.raw" \
          | tail -1 | sed -E 's/.*length=([0-9]+).*/\1/')
  echo "CORE ${name} ${depth:-NA}" >> results/depths.txt
  rm -f "results/synth_${name}.raw"
}

echo "=== Yosys synthesis: area and whole-core depth ==="
core_run single riscv_single_cycle ""                      "${COMMON} ${SINGLE}"
core_run stall  riscv_pipeline     "-chparam FORWARD_EN 0 -chparam PREDICTOR 0" "${COMMON} ${PIPE}"
core_run fwd    riscv_pipeline     "-chparam FORWARD_EN 1 -chparam PREDICTOR 0" "${COMMON} ${PIPE}"
core_run pred   riscv_pipeline     "-chparam FORWARD_EN 1 -chparam PREDICTOR 1" "${COMMON} ${PIPE}"

#--------------------------------------------------------------------------
# B : per-module combinational depth
#--------------------------------------------------------------------------
echo
echo "=== Per-module combinational depth (gate levels) ==="

# $1 label under which the depth is recorded
# $2 module name
# $3 chparam overrides (may be empty)
# $4 source files
mod_depth() {
  local label="$1" mod="$2" chparam="$3" files="$4"
  local d
  d=$(yosys -p "
        read_verilog -I rtl/common ${files} ${BB};
        hierarchy -check -top ${mod} ${chparam};
        synth -flatten;
        ${MAP};
        opt_clean;
        ltp -noff;
      " 2>&1 | grep -i "Longest topological path" | tail -1 \
        | sed -E 's/.*length=([0-9]+).*/\1/')
  printf '  %-20s %s\n' "$label" "${d:-NA}"
  echo "MOD ${label} ${d:-NA}" >> results/depths.txt
}

mod_depth alu              alu              ""  "rtl/common/alu.v"
mod_depth branch_cmp       branch_cmp       ""  "rtl/common/branch_cmp.v"
mod_depth control_unit     control_unit     ""  "rtl/common/control_unit.v"
mod_depth imm_gen          imm_gen          ""  "rtl/common/imm_gen.v"
mod_depth forwarding_unit  forwarding_unit  ""  "rtl/pipelined/forwarding_unit.v"
mod_depth hazard_unit      hazard_unit      ""  "rtl/pipelined/hazard_unit.v"
mod_depth branch_predictor branch_predictor ""  "rtl/pipelined/branch_predictor.v"

# pc_if is measured in BOTH configurations.  With PREDICTOR = 0 the
# target adder and the B-format immediate decoder are unreachable and the
# synthesiser removes them, so measuring only the default would hide the
# entire clock-period cost of the predictor.
mod_depth pc_if            pc_if  "-chparam PREDICTOR 0"  "${COMMON} rtl/pipelined/pc_if.v"
mod_depth pc_if_pred       pc_if  "-chparam PREDICTOR 1"  "${COMMON} rtl/pipelined/pc_if.v"

mod_depth decode_stage     decode_stage  ""  "${COMMON} rtl/pipelined/decode_stage.v"
mod_depth ex_stage         ex_stage      ""  "${COMMON} rtl/pipelined/ex_stage.v"
mod_depth mem_stage        mem_stage     ""  "rtl/pipelined/mem_stage.v"
mod_depth wb_stage         wb_stage      ""  "rtl/pipelined/wb_stage.v"

echo
python3 tools/synth_table.py
