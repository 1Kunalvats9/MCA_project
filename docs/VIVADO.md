# FPGA results: how to get them and how to read them

The project's one remaining measured gap is FPGA utilisation and Fmax.
This document covers what to run, what the numbers mean, and which
specific question the run is supposed to answer.

Mechanics, options and troubleshooting live in [`fpga/README.md`](../fpga/README.md).

---

## 1. Run it

From the project root, on a machine with Vivado (Windows or Linux —
Vivado does not run on macOS; WebPACK is free and supports the parts
used):

```bash
vivado -mode batch -source fpga/run_vivado.tcl
```

```bash
python3 tools/fpga_table.py
```

The first command characterises all four configurations — synthesis plus
full place and route — and writes `results/vivado/fpga.csv`. The second
turns that into `results/fpga_summary.md`, formatted to paste into §7 of
the report.

Budget up to an hour, unattended. No board required; no bitstream is
generated.

---

## 2. Methodology, and why it is set up this way

**Post-route, not post-synthesis.** Post-synthesis timing is optimistic
because it predates placement and routing delays. The script runs
`place_design` and `route_design` before reporting, so the numbers are
real.

**I/O paths excluded from timing.** The cores expose observation outputs
(`pc`, `instr`, `retire_valid`, the performance-counter strobes) purely so
the testbench can watch them; on a real chip they would not be pins. With
a clock defined and no output delay specified, Vivado would time each of
those against the clock with a zero budget, and they could easily become
the reported critical path — corrupting the comparison between
configurations. So the constraints false-path all outputs and the reset
input, leaving register-to-register paths inside the core as the only
timed paths. That is exactly what should be compared.

**Numbers queried, not scraped.** The script reads cell counts and slack
from the in-memory design via `get_cells` and `get_timing_paths` rather
than parsing report text, because report formatting changes between
Vivado versions and object properties do not. Full reports are written
out as well, so anything surprising can be checked by hand.

**Fmax from slack.** `Fmax = 1 / (T_target − WNS)`. A negative WNS means
the target was missed; the derived Fmax is still valid, but re-running
with a longer target period gives the optimiser more room and usually
improves it. Raise the period until WNS is positive but small — that is
the tightest honest figure.

---

## 3. What the run is actually for

Two things, one routine and one that matters.

### 3.1 Replacing the report's only estimated number

§7.5 of the report computes the headline net speedup as

```
speedup = (cycles_single / cycles_cfg) x (T_single / T_cfg)
```

The cycle counts are measured. The clock-period ratio, **1.64x**, is
*estimated* from Yosys gate levels — and gate levels are not nanoseconds.
`tools/fpga_table.py` recomputes the whole table using measured Fmax,
which replaces the last estimated figure in the report with a measured
one.

### 3.2 The question §7.4 cannot answer without this run

This is the interesting one.

Yosys shows the predictor deepening the IF stage from **30 to 56** gate
levels, because IF now contains a B-format immediate decoder and a 32-bit
target adder. 56 is still below the EX stage at **70**, so the critical
path does not move and the predictor is **free in clock period**. That is
why §7.5 reports its 1.30x cycle gain as a straight 1.30x win.

But that conclusion is contingent on *why* EX is 70: Yosys builds the
32-bit ALU adder as a ripple carry. **Vivado maps adders onto dedicated
CARRY4 primitives**, which are far faster, so EX will shrink — and IF may
well overtake it.

So compare the Fmax of `fwd` against `pred`:

| Outcome | Reading | What to do |
|---|---|---|
| Fmax roughly equal | The predictor is free in period on real hardware too; §7.4 holds | Report the 1.30x cycle gain as a real 1.30x |
| `pred` Fmax lower, net still > 1 | IF has become critical; the predictor costs period but still wins overall | Report the net figure; note that moving the target adder into its own stage would recover the rest |
| `pred` Fmax much lower, net < 1 | The period cost exceeds the cycle gain | A genuine negative result. Restructure (target adder in its own stage) rather than dropping the predictor, whose cycle benefit is large |

`fpga_table.py` works out which case applies and writes the corresponding
verdict, including a pointer to `results/vivado/pred_timing_paths.rpt` to
confirm whether the critical path really does now end in the fetch stage.

**§7.4 is written to be confirmed or overturned by this measurement.**
Either outcome is a result worth reporting; what would be weak is leaving
the prediction untested.

---

## 4. Other things to expect

**`dmem` will appear as LUTRAM, not block RAM.** It has an asynchronous
read (§2 of the report), and block RAMs have a registered read port. This
is a predicted consequence of a documented design decision, not a
surprise — `fpga_table.py` checks for it explicitly.

**Carry-cell count confirms the CARRY4 mapping.** A non-zero count is the
direct evidence that §7.3's ripple-carry caveat applies.

**Utilisation should be in the low thousands of LUTs.** If you see tens of
thousands, the memories were synthesised into fabric flip-flops; reduce
`MEM_WORDS` in `rtl/common/defines.vh` to 256 and re-run.

---

## 5. Table to fill in

`tools/fpga_table.py` generates this populated. Shown here so the shape of
the deliverable is clear before the run:

| Configuration | LUTs | FFs | LUTRAM | BRAM | Carry | WNS (ns) | Fmax (MHz) |
|---|---|---|---|---|---|---|---|
| Single-cycle | | | | | | | |
| Pipelined, stall-only | | | | | | | |
| Pipelined, forwarding | | | | | | | |
| Pipelined, fwd + predictor | | | | | | | |

---

## 6. If you would rather use the GUI

The batch flow is strongly preferred — it is reproducible and it records
the methodology. But if you want to click through it:

1. Create an RTL project, part `xc7a35tcpg236-1`.
2. Add all of `rtl/common/*.v`, `rtl/single_cycle/*.v`,
   `rtl/pipelined/*.v` and `fpga/wrappers/cfg_wrappers.v`.
3. Set `rtl/common/defines.vh` to file type **Verilog Header**, and add
   `rtl/common` to Settings → General → Verilog options → Include paths.
   Without this Vivado will not find `defines.vh`.
4. Set the top module to `cfg_single`, `cfg_stall`, `cfg_fwd` or
   `cfg_pred` — one run each.
5. Copy a program's `.imem.hex` / `.dmem.hex` into the project directory
   as `imem_init.hex` / `dmem_init.hex`, and add them as design sources.
6. Add a constraints file containing:

```tcl
create_clock -period 10.000 -name clk [get_ports clk]
set_false_path -from [get_ports rst]
set_false_path -to [all_outputs]
```

7. Run Synthesis, then Implementation. Read utilisation from Implementation
   → Report Utilization and WNS from Report Timing Summary, then compute
   `Fmax = 1 / (10 ns − WNS)`.

Record the numbers in `results/vivado/fpga.csv` using the header that
`fpga/run_vivado.tcl` writes, and `tools/fpga_table.py` will still build
the summary for you.
