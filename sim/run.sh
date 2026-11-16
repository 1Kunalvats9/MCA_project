#!/usr/bin/env bash
#==========================================================================
# run.sh - compile and run one configuration on one program
#
# Usage:
#   ./sim/run.sh <config> <program> [+vcd]
#
#   config  : single | stall | fwd | pred
#   program : base name of a file in programs/ (without .s)
#
# Examples:
#   ./sim/run.sh fwd    dep_chain
#   ./sim/run.sh stall  dep_chain
#   ./sim/run.sh fwd    array_sum +vcd      # also writes a VCD waveform
#==========================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

CFG="${1:-fwd}"
PROG="${2:-independent}"
shift 2 || true

mkdir -p build results

case "$CFG" in
  single) DEFS=(-DCORE_SINGLE) ;;
  stall)  DEFS=(-DCORE_PIPE -DFWD=0 -DPRED=0) ;;
  fwd)    DEFS=(-DCORE_PIPE -DFWD=1 -DPRED=0) ;;
  pred)   DEFS=(-DCORE_PIPE -DFWD=1 -DPRED=1) ;;
  *) echo "unknown config '$CFG' (expected single | stall | fwd | pred)"; exit 1 ;;
esac

# ---- assemble -----------------------------------------------------------
python3 tools/asm.py "programs/${PROG}.s" > /dev/null

# ---- compile ------------------------------------------------------------
iverilog -g2005 -Wall -Wimplicit -Wportbind -Wno-timescale -I rtl/common -s tb_core \
  "${DEFS[@]}" \
  -o "build/tb_core_${CFG}.out" \
  tb/tb_core.v \
  rtl/common/*.v rtl/single_cycle/*.v rtl/pipelined/*.v

# ---- run ----------------------------------------------------------------
# Plain string, not an array: macOS ships bash 3.2, where expanding an
# empty array under "set -u" is an error.
DMEM_ARG=""
if [ -s "programs/${PROG}.dmem.hex" ]; then
  DMEM_ARG="+dmem=programs/${PROG}.dmem.hex"
fi

vvp "build/tb_core_${CFG}.out" \
  "+imem=programs/${PROG}.imem.hex" \
  $DMEM_ARG \
  "+name=${PROG}" "+cfg=${CFG}" \
  "+sig=results/${PROG}.${CFG}.sig" \
  "+vcdfile=results/${PROG}.${CFG}.vcd" \
  "$@"
