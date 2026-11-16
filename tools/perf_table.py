#!/usr/bin/env python3
"""
perf_table.py - turn results/perf.csv into the comparison tables the
report needs.

Prints a human readable summary to stdout and writes results/perf.md
containing markdown tables ready to paste into the report.

Usage: python3 tools/perf_table.py results/perf.csv
"""
import csv
import os
import sys

CFG_LABEL = {
    'single': 'Single-cycle',
    'stall':  'Pipelined (stall only)',
    'fwd':    'Pipelined (forwarding)',
    'pred':   'Pipelined (fwd + 2-bit predictor)',
}
CFG_SHORT = {
    'single': 'Single-cycle',
    'stall':  'Stall only',
    'fwd':    'Forwarding',
    'pred':   'Fwd + predictor',
}
CFG_ORDER = ['single', 'stall', 'fwd', 'pred']


def load(path):
    rows = {}
    progs = []
    with open(path) as f:
        for r in csv.DictReader(f):
            prog, cfg = r['program'], r['config']
            if prog not in progs:
                progs.append(prog)
            rows[(prog, cfg)] = {
                'instructions': int(r['instructions']),
                'cycles': int(r['cycles']),
                'stall_cycles': int(r['stall_cycles']),
                'branches': int(r.get('branches', 0) or 0),
                'taken_branches': int(r['taken_branches']),
                'mispredicts': int(r.get('mispredicts', 0) or 0),
                'cpi': float(r['cpi']),
                'ipc': float(r['ipc']),
            }
    return progs, rows


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'results/perf.csv'
    if not os.path.exists(path):
        print(f"no such file: {path}", file=sys.stderr)
        return 1
    progs, rows = load(path)
    if not rows:
        print("perf.csv is empty", file=sys.stderr)
        return 1

    out = []

    # ---------------- CPI table ----------------
    out.append("## CPI by benchmark and configuration\n")
    out.append("| Benchmark | Instrs | " +
               " | ".join(CFG_SHORT[c] for c in CFG_ORDER) +
               " | Forwarding gain | Predictor gain |")
    out.append("|---|---|" + "---|" * (len(CFG_ORDER) + 2))
    for p in progs:
        base = rows.get((p, 'single'))
        if not base:
            continue
        cells = []
        for c in CFG_ORDER:
            r = rows.get((p, c))
            cells.append(f"{r['cpi']:.3f}" if r else "-")
        st, fw = rows.get((p, 'stall')), rows.get((p, 'fwd'))
        pr = rows.get((p, 'pred'))
        fgain = (f"{st['cycles'] / fw['cycles']:.2f}x"
                 if st and fw and fw['cycles'] else "-")
        pgain = (f"{fw['cycles'] / pr['cycles']:.2f}x"
                 if fw and pr and pr['cycles'] else "-")
        out.append(f"| {p} | {base['instructions']} | " +
                   " | ".join(cells) + f" | {fgain} | {pgain} |")

    # ---------------- cycle count table ----------------
    out.append("\n## Cycle counts\n")
    out.append("| Benchmark | Instrs | " +
               " | ".join(CFG_SHORT[c] for c in CFG_ORDER) + " |")
    out.append("|---|---|" + "---|" * len(CFG_ORDER))
    for p in progs:
        base = rows.get((p, 'single'))
        if not base:
            continue
        cells = []
        for c in CFG_ORDER:
            r = rows.get((p, c))
            cells.append(str(r['cycles']) if r else "-")
        out.append(f"| {p} | {base['instructions']} | " + " | ".join(cells) + " |")

    # ---------------- stall / flush breakdown ----------------
    out.append("\n## Where the cycles go (pipelined configurations)\n")
    out.append("| Benchmark | Config | Instrs | Cycles | Pipeline fill | "
               "Stall cycles | Mispredicts | Flushed slots | Accounted |")
    out.append("|---|---|---|---|---|---|---|---|---|")
    for p in progs:
        for c in ('stall', 'fwd', 'pred'):
            r = rows.get((p, c))
            if not r:
                continue
            fill = 4                       # 5 stages -> 4 cycles of fill
            flushed = r['mispredicts'] * 2
            accounted = r['instructions'] + fill + r['stall_cycles'] + flushed
            mark = "yes" if accounted == r['cycles'] else f"off by {r['cycles']-accounted}"
            out.append(f"| {p} | {CFG_SHORT[c]} | {r['instructions']} | "
                       f"{r['cycles']} | {fill} | {r['stall_cycles']} | "
                       f"{r['mispredicts']} | {flushed} | {mark} |")

    # ---------------- IPC table ----------------
    out.append("\n## IPC by benchmark and configuration\n")
    out.append("| Benchmark | " + " | ".join(CFG_SHORT[c] for c in CFG_ORDER) + " |")
    out.append("|---|" + "---|" * len(CFG_ORDER))
    for p in progs:
        cells = []
        for c in CFG_ORDER:
            r = rows.get((p, c))
            cells.append(f"{r['ipc']:.3f}" if r else "-")
        out.append(f"| {p} | " + " | ".join(cells) + " |")

    # ---------------- averages ----------------
    out.append("\n## Aggregate over all benchmarks\n")
    out.append("| Configuration | Total instrs | Total cycles | "
               "Overall CPI | Overall IPC | Cycles saved vs previous |")
    out.append("|---|---|---|---|---|---|")
    prev = None
    for c in CFG_ORDER:
        ti = sum(r['instructions'] for (p, cc), r in rows.items() if cc == c)
        tc = sum(r['cycles'] for (p, cc), r in rows.items() if cc == c)
        if ti == 0 or tc == 0:
            continue
        if c == 'single' or prev is None:
            delta = "-"
        else:
            delta = f"{prev - tc} ({prev/tc:.2f}x)" if tc else "-"
        out.append(f"| {CFG_LABEL[c]} | {ti} | {tc} | "
                   f"{tc/ti:.3f} | {ti/tc:.3f} | {delta} |")
        prev = tc

    # ---------------- branch prediction accuracy ----------------
    out.append("\n## Branch prediction accuracy\n")
    out.append("Static not-taken (the `fwd` configuration) mispredicts "
               "exactly the taken branches. The 2-bit branch history "
               "table (`pred`) learns each branch's behaviour.\n")
    out.append("| Benchmark | Branches | Taken | Static NT mispredicts | "
               "Static NT accuracy | 2-bit BHT mispredicts | "
               "2-bit BHT accuracy |")
    out.append("|---|---|---|---|---|---|---|")
    tb_total = tm_s = tm_p = tbr = 0
    for p in progs:
        fw, pr = rows.get((p, 'fwd')), rows.get((p, 'pred'))
        if not fw or not pr or fw['branches'] == 0:
            continue
        n = fw['branches']
        a_s = 100.0 * (n - fw['mispredicts']) / n
        a_p = 100.0 * (n - pr['mispredicts']) / n
        tbr += n
        tb_total += fw['taken_branches']
        tm_s += fw['mispredicts']
        tm_p += pr['mispredicts']
        out.append(f"| {p} | {n} | {fw['taken_branches']} | "
                   f"{fw['mispredicts']} | {a_s:.1f}% | "
                   f"{pr['mispredicts']} | {a_p:.1f}% |")
    if tbr:
        out.append(f"| **total** | **{tbr}** | **{tb_total}** | "
                   f"**{tm_s}** | **{100.0*(tbr-tm_s)/tbr:.1f}%** | "
                   f"**{tm_p}** | **{100.0*(tbr-tm_p)/tbr:.1f}%** |")
        out.append("")
        out.append(f"The predictor removes **{tm_s - tm_p} of {tm_s}** "
                   f"mispredictions, worth **{2*(tm_s - tm_p)} cycles** of "
                   f"flushed work.")

    out.append("\n### Note on honest speedup\n")
    out.append("Cycle count alone overstates the benefit of pipelining, "
               "because the single-cycle core needs a much longer clock "
               "period. The fair comparison is")
    out.append("")
    out.append("    speedup = (T_single x cycles_single) / (T_pipe x cycles_pipe)")
    out.append("")
    out.append("with T taken from the synthesis timing report "
               "(see results/synth_*.txt).")

    text = "\n".join(out) + "\n"
    os.makedirs('results', exist_ok=True)
    with open('results/perf.md', 'w') as f:
        f.write(text)
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
