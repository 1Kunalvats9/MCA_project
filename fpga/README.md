# FPGA flow

Everything needed to produce the project's FPGA results. The actual
numbers require Vivado, which does not run on macOS — see
"Where to run this" below.

## One command

From the **project root**, with the programs already assembled
(`./sim/run_all.sh` does that):

```bash
vivado -mode batch -source fpga/run_vivado.tcl
```

Then:

```bash
python3 tools/fpga_table.py
```

That writes `results/fpga_summary.md`, ready to paste into §7 of
`docs/REPORT.md`.

Expect roughly 5–15 minutes per configuration, four configurations, so
budget up to an hour. It is unattended.

## What it does

For each of the four configurations — single-cycle, stall-only,
forwarding, forwarding + predictor — it runs synthesis, then full place
and route, then records:

- LUTs, flip-flops, distributed RAM (LUTRAM), block RAM, carry cells
- worst negative slack, achieved period, and Fmax

Timing is **post-route**, not post-synthesis, so the numbers are real
rather than optimistic.

No bitstream is generated: no board is required and no pinout is
invented.

## Options

```bash
# different part, 15 ns target, different program
vivado -mode batch -source fpga/run_vivado.tcl -tclargs xc7a100tcsg324-1 15.0 fib
```

Positional, all optional: `part`, `period_ns`, `program`. Defaults are
`xc7a35tcpg236-1` (the Basys 3 part), `10.0`, `vecsum64`.

**If any WNS comes out negative**, the design missed the target period.
The reported Fmax is still valid — it is derived from the slack — but
re-running with a longer period gives the tool more room and usually
improves it. Raise the period until WNS is positive but small; that
gives the tightest honest figure.

## Files

| File | Purpose |
|---|---|
| `run_vivado.tcl` | the whole flow; also documents the timing methodology |
| `wrappers/cfg_wrappers.v` | one wrapper per configuration, identical ports |
| `../tools/fpga_table.py` | `fpga.csv` → `results/fpga_summary.md` |

Outputs land in `results/vivado/`: `fpga.csv` plus per-configuration
utilisation and timing reports, and checkpoints (`.dcp`) if anything
needs opening in the GUI.

## Two design notes

**Why wrappers instead of `synth_design -generic`.** Each configuration
becomes a distinct top module, so the Tcl is a plain loop and the
parameter values can be checked by reading the source rather than trusted
to a command-line flag. All four have identical port lists, so one
constraints file covers every run.

**Why the memories are initialised with a real program.** The instruction
memory is a ROM initialised by `$readmemh`. With an empty image every
word reads as zero — the halt word — and the synthesiser would correctly
optimise most of the processor away, making the utilisation figures
meaningless. The script copies the chosen program's hex images into the
run directory as `imem_init.hex` / `dmem_init.hex`, which is what the
wrappers reference, so no absolute paths are baked into the RTL.

## Where to run this

Vivado runs on Windows and Linux, not macOS, so this has to be run by a
team member on one of those. Vivado WebPACK is free and the Artix-7 parts
above are supported by it. No board is needed.

## If `$readmemh` fails to find the hex files

The wrappers use bare relative filenames and the script `cd`s into the
run directory first, which is the arrangement Vivado handles most
predictably. If your Vivado version still cannot find them, the fallback
is to add the two copied files in `results/vivado/` to the project as
design sources, or to pass absolute paths:

```tcl
synth_design -top cfg_pred -part $part -include_dirs $incdir \
  -generic IMEM_HEX=/absolute/path/imem_init.hex \
  -generic DMEM_HEX=/absolute/path/dmem_init.hex
```

## Checking the script before a long run

The Tcl was validated under plain `tclsh` with a stub harness that
defines every Vivado command as a no-op, which confirms the control flow,
file handling and Fmax arithmetic are correct. It has **not** been run
against real Vivado — no Vivado was available on the development machine.
If something fails, it will be a tool-interaction detail rather than a
logic error, and the troubleshooting notes above cover the likely ones.
