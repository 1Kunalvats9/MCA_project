#!/usr/bin/env python3
"""
synth_table.py - build results/synth_summary.md from the Yosys logs.

Reads results/synth_<cfg>.txt (cell counts) and results/depths.txt
(logic depths) and writes a markdown summary for the report.

Usage: python3 tools/synth_table.py
"""
import os
import re

CFGS = [('single', 'Single-cycle'),
        ('stall',  'Pipelined (stall only)'),
        ('fwd',    'Pipelined (forwarding)'),
        ('pred',   'Pipelined (fwd + 2-bit predictor)')]

# The five pipeline stages, in order, for the clock-period argument.
STAGES = ['pc_if', 'decode_stage', 'ex_stage', 'mem_stage', 'wb_stage']
# With the predictor enabled, IF contains an extra adder and immediate
# decoder, so the stage set that determines the clock period changes.
STAGES_PRED = ['pc_if_pred', 'decode_stage', 'ex_stage', 'mem_stage',
               'wb_stage']

FF_TYPES = ('$_DFF', '$_SDFF', '$_DFFE', '$_SDFFE', '$_SDFFCE', '$_ALDFF')


def parse_stat(path):
    """Return (total_cells, flip_flops, {celltype: count}).

    The log can contain MORE THAN ONE stat block: the `synth` script
    prints its own stat, and synth.sh then runs an explicit one after
    `abc`.  Only the last block describes the final mapped netlist, so
    everything before the last "=== <module> ===" header is discarded.
    Summing across blocks instead (the original bug) double-counted every
    flip-flop and multiplexer while leaving the total cell count correct,
    because that one was assigned rather than accumulated - an
    inconsistency that is easy to miss and hard to spot in a table.
    """
    if not os.path.exists(path):
        return None
    with open(path) as f:
        lines = f.read().splitlines()

    last_hdr = -1
    for i, line in enumerate(lines):
        if line.strip().startswith('===') and line.strip().endswith('==='):
            last_hdr = i
    if last_hdr >= 0:
        lines = lines[last_hdr:]

    cells, ffs, breakdown = 0, 0, {}
    for line in lines:
        if True:
            m = re.match(r'\s*(\d+)\s+cells\s*$', line)
            if m:
                cells = int(m.group(1))
                continue
            m = re.match(r'\s*(\d+)\s+(\$_\S+)\s*$', line)
            if m:
                n, t = int(m.group(1)), m.group(2)
                breakdown[t] = breakdown.get(t, 0) + n
                if t.startswith(FF_TYPES):
                    ffs += n
    return cells, ffs, breakdown


def parse_depths(path):
    core, mod = {}, {}
    if not os.path.exists(path):
        return core, mod
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 3:
                continue
            kind, name, val = parts
            v = int(val) if val.isdigit() else None
            (core if kind == 'CORE' else mod)[name] = v
    return core, mod


def main():
    core_depth, mod_depth = parse_depths('results/depths.txt')
    agg = {}
    out = ["# Synthesis results (Yosys, generic gate library)\n"]

    # ---------------- area ----------------
    out.append("## Area\n")
    out.append("Memories are blackboxed: on an FPGA the instruction and data "
               "memories map to block RAM, not to fabric logic. The 32x32 "
               "register file IS included, which is why the flip-flop counts "
               "all start from roughly 1024.\n")
    out.append("| Configuration | Total cells | Flip-flops | "
               "Multiplexers | Whole-core depth (gate levels) |")
    out.append("|---|---|---|---|---|")
    stats = {}
    for key, label in CFGS:
        st = parse_stat(f'results/synth_{key}.txt')
        if not st:
            continue
        cells, ffs, bd = st
        stats[key] = (cells, ffs, bd)
        muxes = sum(v for k, v in bd.items() if 'MUX' in k)
        d = core_depth.get(key)
        out.append(f"| {label} | {cells} | {ffs} | {muxes} | "
                   f"{d if d is not None else '-'} |")

    # ---------------- cost of each feature ----------------
    if 'single' in stats and 'stall' in stats and 'fwd' in stats:
        out.append("\n## What each feature costs\n")
        sc, sf, _ = stats['single']
        tc, tf, _ = stats['stall']
        fc, ff, _ = stats['fwd']
        out.append("| Change | Extra cells | Extra flip-flops |")
        out.append("|---|---|---|")
        out.append(f"| Single-cycle -> pipelined (the 4 pipeline registers "
                   f"and hazard unit) | {tc - sc:+d} | {tf - sf:+d} |")
        out.append(f"| Adding the forwarding network | {fc - tc:+d} | "
                   f"{ff - tf:+d} |")
        if 'pred' in stats:
            pc_, pf, _ = stats['pred']
            out.append(f"| Adding the 2-bit branch predictor | "
                       f"{pc_ - fc:+d} | {pf - ff:+d} |")
            out.append(f"| Single-cycle -> fully featured pipeline (total) "
                       f"| {pc_ - sc:+d} | {pf - sf:+d} |")
        else:
            out.append(f"| Single-cycle -> pipelined with forwarding (total) "
                       f"| {fc - sc:+d} | {ff - sf:+d} |")

    # ---------------- per-stage depth ----------------
    out.append("\n## Per-stage combinational depth\n")
    out.append("Each module synthesised standalone. The DEEPEST stage sets "
               "the pipelined clock period; the SUM of the five sets the "
               "single-cycle clock period.\n")
    out.append("| Module | Role | Depth (gate levels) |")
    out.append("|---|---|---|")
    roles = {
        'pc_if': 'IF stage',
        'decode_stage': 'ID stage',
        'ex_stage': 'EX stage',
        'mem_stage': 'MEM stage',
        'wb_stage': 'WB stage',
        'alu': 'inside EX',
        'branch_cmp': 'inside EX',
        'control_unit': 'inside ID',
        'imm_gen': 'inside ID',
        'forwarding_unit': 'hazard control',
        'hazard_unit': 'hazard control',
        'branch_predictor': 'BHT, read in IF',
        'pc_if_pred': 'IF stage, predictor enabled',
    }
    for name in STAGES + ['pc_if_pred', 'alu', 'branch_cmp',
                          'control_unit', 'imm_gen', 'forwarding_unit',
                          'hazard_unit', 'branch_predictor']:
        d = mod_depth.get(name)
        marker = ' **(deepest stage)**' if name in STAGES and d is not None \
            and d == max((mod_depth.get(s) or 0) for s in STAGES) else ''
        out.append(f"| `{name}` | {roles.get(name,'')}{marker} | "
                   f"{d if d is not None else '-'} |")

    # ---- what the predictor does to the clock period ----
    pv = [mod_depth.get(s) for s in STAGES_PRED]
    sv0 = [mod_depth.get(s) for s in STAGES]
    if all(v is not None for v in pv) and all(v is not None for v in sv0):
        out.append("\n### What the predictor costs in clock period\n")
        out.append(f"- Deepest stage WITHOUT the predictor: "
                   f"**{max(sv0)}** (`{STAGES[sv0.index(max(sv0))]}`)")
        out.append(f"- Deepest stage WITH the predictor: "
                   f"**{max(pv)}** (`{STAGES_PRED[pv.index(max(pv))]}`)")
        if max(pv) > max(sv0):
            out.append(f"- The predictor lengthens the critical path by "
                       f"**{max(pv) - max(sv0)}** gate levels "
                       f"({100.0*(max(pv)-max(sv0))/max(sv0):.0f}%), "
                       f"because IF now contains a B-format immediate "
                       f"decoder and a 32-bit target adder.")
            out.append(f"- Net effect: it saves "
                       f"{'cycles' if True else ''} but costs period, so "
                       f"the two must be multiplied, not compared "
                       f"separately. See the net speedup table below.")
        else:
            out.append("- The predictor does NOT lengthen the critical "
                       "path: the EX stage (the ALU adder) still "
                       "dominates, so the extra IF logic is absorbed. "
                       "The predictor is effectively free in clock "
                       "period for this design.")

    stage_vals = [mod_depth.get(s) for s in STAGES]
    if all(v is not None for v in stage_vals):
        deepest = max(stage_vals)
        total = sum(stage_vals)
        out.append(f"\n- Sum of all five stages (single-cycle path): "
                   f"**{total}** gate levels")
        out.append(f"- Deepest single stage (pipelined path): "
                   f"**{deepest}** gate levels")
        if deepest:
            ratio = total / deepest
            out.append(f"- Implied clock-period ratio: "
                       f"**{ratio:.2f}x** shorter period when pipelined")
            out.append("")
            out.append("### Honest speedup")
            out.append("")
            out.append("    speedup = (T_single x cycles_single) "
                       "/ (T_pipe x cycles_pipe)")
            out.append("")
            out.append(f"Using T_single / T_pipe = {ratio:.2f} and the "
                       f"aggregate cycle counts from results/perf.md:")
            out.append("")
            out.append("| Comparison | Cycle ratio | Clock ratio | "
                       "Net speedup |")
            out.append("|---|---|---|---|")
            # aggregate cycles come from perf.csv if present
            if os.path.exists('results/perf.csv'):
                import csv
                with open('results/perf.csv') as f:
                    for r in csv.DictReader(f):
                        agg[r['config']] = agg.get(r['config'], 0) + \
                            int(r['cycles'])
            head = 'pred' if 'pred' in agg and agg.get('pred') else 'fwd'
            if 'single' in agg and head in agg and agg[head]:
                cyc_ratio = agg['single'] / agg[head]
                out.append(f"| Single-cycle vs pipelined ({head}) | "
                           f"{cyc_ratio:.3f}x | {ratio:.2f}x | "
                           f"**{cyc_ratio * ratio:.2f}x** |")
            if 'stall' in agg and 'fwd' in agg and agg['fwd']:
                out.append(f"| Pipelined stall-only vs forwarding | "
                           f"{agg['stall']/agg['fwd']:.3f}x | 1.00x "
                           f"(same stages) | "
                           f"**{agg['stall']/agg['fwd']:.2f}x** |")
            if 'fwd' in agg and 'pred' in agg and agg['pred']:
                # The predictor's clock ratio is measured, not assumed: it
                # deepens IF, so it is 1.00x only while IF stays under the
                # deepest stage.  Computed here rather than asserted.
                d_ifp = mod_depth.get('pc_if_pred')
                d_deep = max(v for v in sv0 if v is not None) \
                    if 'sv0' in dir() else None
                deep_wo = max(mod_depth.get(x) for x in STAGES)
                deep_w = max([mod_depth.get(x) for x in STAGES_PRED])
                if deep_w and deep_wo:
                    pclk = deep_wo / deep_w
                    note = ("1.00x (IF deepens to %d but stays under the "
                            "%d-level EX stage)" % (d_ifp, deep_wo)) \
                        if deep_w == deep_wo else \
                        ("%.2fx (IF at %d is now the critical stage)"
                         % (pclk, d_ifp))
                    out.append(f"| Forwarding vs forwarding+predictor | "
                               f"{agg['fwd']/agg['pred']:.3f}x | {note} | "
                               f"**{agg['fwd']/agg['pred']*pclk:.2f}x** |")
                out.append("")
                d0 = mod_depth.get('pc_if')
                d1 = mod_depth.get('pc_if_pred')
                dex = mod_depth.get('ex_stage')
                if d0 and d1 and dex:
                    if d1 <= dex:
                        out.append(
                            f"The predictor adds an immediate decoder and "
                            f"a target adder to IF, taking that stage from "
                            f"{d0} to {d1} gate levels. That is still "
                            f"below the EX stage at {dex}, so the critical "
                            f"path does not move and the clock ratio is "
                            f"unchanged: for this design the predictor's "
                            f"cycle saving is a genuine net win.")
                    else:
                        out.append(
                            f"The predictor takes IF from {d0} to {d1} "
                            f"gate levels, which EXCEEDS the EX stage at "
                            f"{dex}. IF is now the critical path, so the "
                            f"clock period grows and the cycle saving is "
                            f"partly given back. Splitting the target "
                            f"adder out of IF would recover it.")

    # ---------------- memory-delay sensitivity ----------------
    head = 'pred' if agg.get('pred') else 'fwd'
    sens_stages = STAGES_PRED if head == 'pred' else STAGES
    sens_vals = [mod_depth.get(x) for x in sens_stages]

    if all(v is not None for v in sens_vals) and agg.get('single') \
            and agg.get(head):
        d_if, d_id, d_ex, d_mem, d_wb = sens_vals
        # T_single uses the SINGLE-CYCLE core's own stage depths.  That
        # core has no predictor, so its fetch path is the plain pc_if
        # depth, not the deeper predictor-enabled one.  Using the
        # predictor's IF depth here would charge the single-cycle core for
        # hardware it does not contain.
        total_path = sum(mod_depth.get(x) for x in STAGES)
        cyc_ratio = agg['single'] / agg[head]

        out.append("\n## Sensitivity to memory access delay\n")
        out.append("The table above excludes memory access time, which "
                   "flatters the single-cycle core: its critical path "
                   "contains an instruction fetch AND a data access in "
                   "series, while no single pipeline stage contains "
                   "both.\n")
        out.append(f"T_single is the single-cycle core's own path "
                   f"({total_path} levels, IF = "
                   f"{mod_depth.get('pc_if')}); T_pipe is the `{head}` "
                   f"configuration, whose IF stage is {d_if} levels deep "
                   f"because the predictor adds a target adder there. "
                   f"Writing M for the memory read delay:\n")
        out.append(f"    T_single  ~  IF + ID + EX + MEM + WB + 2M"
                   f"   =  {total_path} + 2M")
        out.append(f"    T_pipe    ~  max(IF+M, ID, EX, MEM+M, WB)"
                   f"   =  max({d_if}+M, {d_id}, {d_ex}, {d_mem}+M, {d_wb})")
        out.append("")
        out.append(f"Cycle ratio is held at {cyc_ratio:.3f}x, the measured "
                   f"single-cycle / `{head}` figure.\n")
        out.append("| Memory delay M | T_single | T_pipe | Clock ratio | "
                   "Critical stage | Net speedup vs single-cycle |")
        out.append("|---|---|---|---|---|---|")
        for M in (0, 10, 20, 40, 60, 80):
            t_s = total_path + 2 * M
            cands = {'IF': d_if + M, 'ID': d_id, 'EX': d_ex,
                     'MEM': d_mem + M, 'WB': d_wb}
            t_p = max(cands.values())
            crit = max(cands, key=lambda k: cands[k])
            ratio = t_s / t_p
            out.append(f"| {M} | {t_s} | {t_p} | {ratio:.2f}x | {crit} | "
                       f"**{cyc_ratio * ratio:.2f}x** |")
        out.append("")
        out.append("Two things to read off this table:\n")
        out.append("1. **Pipelining only pays once the stages it "
                   "separates are genuinely expensive.** At M = 0 the "
                   "cycle count rises by nearly as much as the clock "
                   "period falls. Any realistic memory makes pipelining "
                   "clearly worthwhile.")
        first_if = next((M for M in (0, 10, 20, 40, 60, 80)
                         if d_if + M > d_ex), None)
        if first_if is not None:
            out.append(f"2. **Past M = {first_if} the critical stage moves "
                       f"from EX to IF**, and the clock ratio stops "
                       f"improving. Beyond that point the way to go "
                       f"faster is not to re-balance these five stages "
                       f"but to make memory access cheaper, or to split "
                       f"fetch across more stages - which is exactly why "
                       f"real processors have caches and why deeper "
                       f"pipelines break fetch and memory into several "
                       f"stages each.")
            if head == 'pred':
                out.append(f"   Note that the predictor brings this "
                           f"crossover forward: it deepens IF from "
                           f"{mod_depth.get('pc_if')} to {d_if} levels, so "
                           f"IF becomes critical at a smaller M than it "
                           f"would without the predictor. The predictor is "
                           f"free in clock period today only because the "
                           f"ripple-carry ALU is so deep.")

    # ---------------- caveats ----------------
    out.append("\n## Caveats on these numbers\n")
    out.append("1. **Gate levels are not nanoseconds.** The generic library "
               "has no timing model, so a 2-input gate and a wide "
               "multiplexer count the same. These are structural "
               "comparisons.")
    out.append("2. **The adder dominates.** Yosys builds the 32-bit ALU "
               "adder as a ripple carry, so its carry chain is the deepest "
               "thing in the design and it sits in one stage (EX). That is "
               "why the whole-core depths of the three configurations are "
               "close together: every one of them contains the same adder. "
               "It also identifies the real bottleneck - to raise Fmax "
               "further you would replace the adder, not re-balance the "
               "stages.")
    out.append("3. **Memory access time is excluded.** With the memories "
               "blackboxed, the single-cycle core's path does not include "
               "an instruction fetch followed by a data access, which in "
               "reality is its largest cost. The single-cycle clock period "
               "reported here is therefore optimistic, and the real "
               "advantage of pipelining is larger than these figures show.")
    out.append("4. **For the FPGA deliverable**, run Vivado on this RTL to "
               "get LUT/FF utilisation and a real Fmax. Vivado maps the "
               "adder onto carry-chain primitives, which changes the "
               "balance described in point 2. Note that `dmem` has an "
               "asynchronous read and will map to distributed LUT RAM "
               "rather than block RAM - see the header comment in "
               "rtl/common/dmem.v.")

    text = "\n".join(out) + "\n"
    os.makedirs('results', exist_ok=True)
    with open('results/synth_summary.md', 'w') as f:
        f.write(text)
    print(text)


if __name__ == '__main__':
    main()
