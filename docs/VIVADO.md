# FPGA synthesis with Vivado

The `synthesis/FPGA results` deliverable needs LUT and flip-flop
utilisation and a real Fmax. Yosys (`./sim/synth.sh`) gives
technology-independent area and logic depth, but it has no timing model —
see §7.6 of the report. This file has the steps for real numbers.

Vivado WebPACK is free and runs on Windows and Linux. One team member
with either is enough; nothing here needs a physical board.

## 1. Project setup

Create an RTL project targeting any Artix-7 part (for example
`xc7a35tcpg236-1`, the Basys 3 part). Add as design sources:

```
rtl/common/defines.vh        (set type to "Verilog Header")
rtl/common/alu.v
rtl/common/branch_cmp.v
rtl/common/control_unit.v
rtl/common/imm_gen.v
rtl/common/regfile.v
rtl/common/imem.v
rtl/common/dmem.v
rtl/pipelined/*.v
```

Set `riscv_pipeline` as the top module. Add `rtl/common` to the include
directories (Settings → General → Verilog options → Include paths), or
Vivado will not find `defines.vh`.

For the single-cycle comparison, use `rtl/single_cycle/riscv_single_cycle.v`
as top instead, with `rtl/common/*.v`.

## 2. Loading a program

`imem` uses `$readmemh`, which Vivado supports for synthesis. Set the
`IMEM_HEX` parameter on the top module to an absolute path to one of the
`programs/*.imem.hex` files, or add the hex file as a design source and
use a bare filename. Same for `DMEM_HEX` on the data memory.

If `$readmemh` gives trouble, the fallback is to generate an initialised
array: `python3 tools/asm.py` already emits one word per line, so a short
script can turn it into an `initial begin mem[0] = 32'h...; end` block.

## 3. Runs to do

Run **Synthesis** then **Implementation** for each of four
configurations. The three pipelined ones differ only by parameters, set in
Settings → Synthesis → More Options:

```
-generic FORWARD_EN=0 -generic PREDICTOR=0     (stall-only)
-generic FORWARD_EN=1 -generic PREDICTOR=0     (forwarding)
-generic FORWARD_EN=1 -generic PREDICTOR=1     (forwarding + predictor)
```

Or instantiate `riscv_pipeline #(.FORWARD_EN(1), .PREDICTOR(1))` in a thin
wrapper, which is less fiddly.

## 4. Numbers to collect

| Number | Where |
|---|---|
| LUTs, FFs, LUTRAM, BRAM | Implementation → Report Utilization |
| Worst negative slack (WNS) | Implementation → Report Timing Summary |
| Fmax | compute it, see below |

Create a clock constraint first, otherwise there is nothing to report
against. A 100 MHz starting point, in a new XDC file:

```tcl
create_clock -period 10.000 -name clk [get_ports clk]
```

Then:

```
Fmax = 1 / (T_target - WNS)
```

With `T_target = 10 ns`: if WNS is +2.0 ns, the design closes at 8.0 ns,
so Fmax ≈ 125 MHz. If WNS is negative the design failed timing at 100 MHz
— raise the period and re-run until WNS is positive but small, which
gives the tightest honest figure.

## 5. Expected findings, and what to do with them

**The ALU adder will stop dominating, and this is the thing to watch.**
Yosys builds a ripple-carry adder, which is why EX shows 70 of the 115
total gate levels in §7.3 of the report. Vivado maps `+` onto dedicated
CARRY4 primitives, far faster than generic logic, so EX will shrink
relative to the others.

That matters most for the **predictor configuration**. §7.4 of the report
shows the predictor takes the IF stage from 30 to 56 gate levels, because
IF now contains a B-format immediate decoder and a 32-bit target adder.
Today that is free, because 56 is still under EX's 70. Once Vivado
shortens EX with carry chains, **IF may well become the critical path**,
and the predictor's clock-period cost becomes real.

So the key comparison to extract is the Fmax of `fwd` against `pred`:

- **If Fmax is roughly equal**, the predictor is free in period as well as
  in cycles, and the 1.30x cycle gain is a 1.30x real gain. Say so.
- **If `pred` has a noticeably lower Fmax**, multiply it out:
  `1.30 x (Fmax_pred / Fmax_fwd)`. If that product is still above 1, the
  predictor is worth keeping; if not, the fix is to move the target adder
  into its own stage rather than to drop the predictor, whose cycle
  benefit is large. Either way this is a genuine engineering finding and
  §7.4 is written to be confirmed or overturned by it.

Check the timing report's critical path endpoints to see which stage it
actually lands in — that is the single most informative number you will
get out of Vivado.

**`dmem` will appear as LUTRAM, not BRAM.** It has an asynchronous read
(see §2 of the report and the header of `rtl/common/dmem.v`). `imem` is
read-only and may infer as ROM in LUTs or BRAM depending on how Vivado
feels about the initialisation. Report what you actually get; do not
assume.

**Utilisation should be small** — low thousands of LUTs. If you see tens
of thousands, the memories were synthesised into fabric flip-flops;
reduce `MEM_WORDS` in `defines.vh` to 256 and re-run.

## 6. Table to fill in for the report

Add this to §7 once the runs finish:

| Configuration | LUTs | FFs | LUTRAM | BRAM | T_target (ns) | WNS (ns) | Fmax (MHz) |
|---|---|---|---|---|---|---|---|
| Single-cycle | | | | | | | |
| Pipelined, stall-only | | | | | | | |
| Pipelined, forwarding | | | | | | | |
| Pipelined, fwd + predictor | | | | | | | |

Then recompute the net speedup in §7.4 using the measured Fmax ratio in
place of the estimated 1.64x clock ratio. That replaces the only estimated
number in the report with a measured one, and it is likely to turn the
break-even result in §7.4 into a clear win — the sensitivity analysis in
§7.5 predicts why.
