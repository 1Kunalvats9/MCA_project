#!/usr/bin/env python3
"""
fpga_table.py - turn results/vivado/fpga.csv into the report's FPGA section.

Reads the CSV written by fpga/run_vivado.tcl, plus results/perf.csv for
the cycle counts, and writes results/fpga_summary.md.

The important thing it does is recompute the project's headline net
speedup using the MEASURED Fmax in place of the gate-level clock-period
estimate from Yosys. That replaces the only estimated number in the
report with a measured one.

Usage: python3 tools/fpga_table.py
"""
import csv
import os
import sys

CSV = 'results/vivado/fpga.csv'
PERF = 'results/perf.csv'
OUT = 'results/fpga_summary.md'

LABEL = {
    'single': 'Single-cycle',
    'stall':  'Pipelined (stall only)',
    'fwd':    'Pipelined (forwarding)',
    'pred':   'Pipelined (fwd + 2-bit predictor)',
}
ORDER = ['single', 'stall', 'fwd', 'pred']

# Predictions made from the Yosys gate-level numbers, in docs/REPORT.md
# §7.3 and §7.4, which the FPGA run either confirms or overturns.
YOSYS_CLOCK_RATIO = 1.64      # T_single / T_pipe, gate levels
YOSYS_IF_PLAIN = 30
YOSYS_IF_PRED = 56
YOSYS_EX = 70


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def main():
    if not os.path.exists(CSV):
        print(f"{CSV} not found.\n"
              f"Run the Vivado flow first, from the project root:\n"
              f"    vivado -mode batch -source fpga/run_vivado.tcl",
              file=sys.stderr)
        return 1

    rows = {}
    with open(CSV) as f:
        for r in csv.DictReader(f):
            rows[r['config']] = r

    cycles = {}
    if os.path.exists(PERF):
        with open(PERF) as f:
            for r in csv.DictReader(f):
                cycles[r['config']] = cycles.get(r['config'], 0) + int(r['cycles'])

    out = ["# FPGA results (Vivado, post-route)\n"]

    part = "unknown"
    period = rows.get('pred', rows.get('fwd', {})).get('period_ns', '?')
    out.append(f"Target period {period} ns. Timing is post-place-and-route, "
               f"not post-synthesis, so these are real numbers rather than "
               f"optimistic estimates. I/O paths are excluded from timing "
               f"(see the methodology note in `fpga/run_vivado.tcl`), so "
               f"the figures describe register-to-register logic inside "
               f"the core, which is what should be compared between "
               f"configurations.\n")

    # ---------------- utilisation ----------------
    out.append("## Utilisation and achieved frequency\n")
    out.append("| Configuration | LUTs | Flip-flops | LUTRAM | BRAM | "
               "Carry cells | WNS (ns) | Achieved (ns) | Fmax (MHz) |")
    out.append("|---|---|---|---|---|---|---|---|---|")
    for c in ORDER:
        r = rows.get(c)
        if not r:
            continue
        out.append(f"| {LABEL[c]} | {r['luts']} | {r['ffs']} | "
                   f"{r['lutram']} | {r['bram']} | {r['carry']} | "
                   f"{r['wns_ns']} | {r['achieved_ns']} | "
                   f"**{r['fmax_mhz']}** |")

    missed = [c for c in ORDER
              if rows.get(c) and (num(rows[c]['wns_ns']) or 0) < 0]
    if missed:
        out.append("")
        out.append(f"**Timing not met** for: "
                   f"{', '.join(LABEL[c] for c in missed)}. The achieved "
                   f"period and Fmax above are still valid (they are "
                   f"derived from the slack), but re-running with a longer "
                   f"target period will give the tool room to optimise "
                   f"and may improve them.")

    # ---------------- cost of each feature ----------------
    out.append("\n## What each feature costs on real hardware\n")
    out.append("| Change | Extra LUTs | Extra flip-flops | Fmax change |")
    out.append("|---|---|---|---|")
    steps = [('single', 'stall', 'Single-cycle -> pipelined'),
             ('stall', 'fwd', 'Adding the forwarding network'),
             ('fwd', 'pred', 'Adding the 2-bit branch predictor')]
    for a, b, name in steps:
        ra, rb = rows.get(a), rows.get(b)
        if not ra or not rb:
            continue
        dl = int(rb['luts']) - int(ra['luts'])
        df = int(rb['ffs']) - int(ra['ffs'])
        fa, fb = num(ra['fmax_mhz']), num(rb['fmax_mhz'])
        dfm = (f"{fa:.1f} -> {fb:.1f} MHz ({100.0*(fb-fa)/fa:+.1f}%)"
               if fa and fb else "-")
        out.append(f"| {name} | {dl:+d} | {df:+d} | {dfm} |")

    # ---------------- the headline recomputation ----------------
    if cycles and rows.get('single') and num(rows['single']['fmax_mhz']):
        out.append("\n## Net speedup, with measured Fmax\n")
        out.append("This replaces the gate-level clock-period estimate "
                   f"({YOSYS_CLOCK_RATIO}x) used in §7.5 of the report "
                   "with the measured ratio:\n")
        out.append("    speedup = (cycles_single / cycles_cfg) "
                   "x (Fmax_cfg / Fmax_single)\n")
        out.append("| Configuration | Cycles | Cycle ratio | Fmax (MHz) | "
                   "Clock ratio | Net speedup |")
        out.append("|---|---|---|---|---|---|")
        f_s = num(rows['single']['fmax_mhz'])
        c_s = cycles.get('single')
        for c in ORDER:
            r = rows.get(c)
            if not r or c not in cycles or not num(r['fmax_mhz']):
                continue
            cyc_ratio = c_s / cycles[c]
            clk_ratio = num(r['fmax_mhz']) / f_s
            out.append(f"| {LABEL[c]} | {cycles[c]} | {cyc_ratio:.3f}x | "
                       f"{r['fmax_mhz']} | {clk_ratio:.2f}x | "
                       f"**{cyc_ratio*clk_ratio:.2f}x** |")

    # ---------------- did Yosys predict correctly? ----------------
    out.append("\n## Checking the gate-level predictions\n")
    rf, rp = rows.get('fwd'), rows.get('pred')
    rs = rows.get('single')

    if rs and rf and num(rs['fmax_mhz']) and num(rf['fmax_mhz']):
        measured = num(rf['fmax_mhz']) / num(rs['fmax_mhz'])
        out.append(f"**Clock-period ratio.** Yosys gate levels predicted "
                   f"{YOSYS_CLOCK_RATIO}x; Vivado measures "
                   f"**{measured:.2f}x** "
                   f"(single-cycle {rs['fmax_mhz']} MHz vs forwarding "
                   f"{rf['fmax_mhz']} MHz). "
                   + ("The estimate held up." if abs(measured - YOSYS_CLOCK_RATIO) < 0.35
                      else "The estimate was off, which is expected: see "
                           "the carry-chain note below.") + "\n")

    if rf and num(rf['carry']):
        out.append(f"**Carry chains.** The forwarding configuration uses "
                   f"{rf['carry']} carry cells, confirming Vivado mapped "
                   f"the adders onto CARRY4 primitives rather than generic "
                   f"logic. §7.3 of the report predicted this would shrink "
                   f"the EX stage relative to the Yosys ripple-carry "
                   f"figure of {YOSYS_EX} gate levels.\n")

    if rf and rp and num(rf['fmax_mhz']) and num(rp['fmax_mhz']):
        ff, fp = num(rf['fmax_mhz']), num(rp['fmax_mhz'])
        drop = 100.0 * (ff - fp) / ff          # positive when Fmax falls
        delta = 100.0 * (fp - ff) / ff         # signed change in Fmax
        out.append(f"**The predictor's clock-period cost — the key "
                   f"question from §7.4.** Yosys showed the predictor "
                   f"deepening IF from {YOSYS_IF_PLAIN} to "
                   f"{YOSYS_IF_PRED} gate levels, still under the EX "
                   f"stage at {YOSYS_EX}, and therefore free. Vivado "
                   f"shortens EX with carry chains, so IF may become "
                   f"critical.\n")
        out.append(f"Measured: {ff:.1f} MHz without the predictor, "
                   f"{fp:.1f} MHz with it — a {delta:+.1f}% change in "
                   f"Fmax.\n")
        cyc_gain = (cycles.get('fwd', 0) / cycles['pred']
                    if cycles.get('pred') else None)
        if cyc_gain:
            net = cyc_gain * (fp / ff)
            if drop < 2.0:
                out.append(f"The predictor is **free in clock period on "
                           f"real hardware too**, so its {cyc_gain:.2f}x "
                           f"cycle gain is a genuine **{net:.2f}x** "
                           f"speedup. §7.4's conclusion holds.")
            elif net > 1.0:
                out.append(f"IF has become the critical path, so the "
                           f"predictor now costs clock period: the "
                           f"{cyc_gain:.2f}x cycle gain nets out to "
                           f"**{net:.2f}x**. Still worth keeping, but "
                           f"§7.4's \"free\" conclusion is overturned — "
                           f"moving the target adder into its own stage "
                           f"would recover the difference. Check "
                           f"`results/vivado/pred_timing_paths.rpt` to "
                           f"confirm the critical path now ends in the "
                           f"fetch stage.")
            else:
                out.append(f"The clock-period cost **exceeds** the cycle "
                           f"gain: {cyc_gain:.2f}x cycles x "
                           f"{fp/ff:.2f}x clock = **{net:.2f}x**, i.e. a "
                           f"net loss. The predictor should either be "
                           f"restructured (target adder in its own stage) "
                           f"or dropped. This is a real finding and worth "
                           f"reporting as one.")

    if rp and int(rp['bram']) == 0 and int(rp['lutram']) > 0:
        out.append(f"\n**Memory inference.** {rp['lutram']} LUTRAM cells "
                   f"and no block RAM, exactly as §2 of the report "
                   f"predicted: `dmem` has an asynchronous read, so it "
                   f"cannot map to a block RAM, whose read port is "
                   f"registered.")
    elif rp and int(rp['bram']) > 0:
        out.append(f"\n**Memory inference.** {rp['bram']} block RAM tiles "
                   f"were inferred. Worth checking which memory went to "
                   f"BRAM — §2 of the report predicts `dmem` cannot, "
                   f"because of its asynchronous read, so this is most "
                   f"likely the read-only `imem`.")

    out.append("\n---\n")
    out.append("Generated by `tools/fpga_table.py` from "
               "`results/vivado/fpga.csv`. Full Vivado reports are in "
               "`results/vivado/`.")

    text = "\n".join(out) + "\n"
    os.makedirs('results', exist_ok=True)
    with open(OUT, 'w') as f:
        f.write(text)
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
