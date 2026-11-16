# Synthesis results (Yosys, generic gate library)

## Area

Memories are blackboxed: on an FPGA the instruction and data memories map to block RAM, not to fabric logic. The 32x32 register file IS included, which is why the flip-flop counts all start from roughly 1024.

| Configuration | Total cells | Flip-flops | Multiplexers | Whole-core depth (gate levels) |
|---|---|---|---|---|
| Single-cycle | 4431 | 1056 | 1891 | 78 |
| Pipelined (stall only) | 5928 | 1469 | 1519 | 68 |
| Pipelined (forwarding) | 6216 | 1469 | 1563 | 77 |
| Pipelined (fwd + 2-bit predictor) | 7287 | 1605 | 1638 | 79 |

## What each feature costs

| Change | Extra cells | Extra flip-flops |
|---|---|---|
| Single-cycle -> pipelined (the 4 pipeline registers and hazard unit) | +1497 | +413 |
| Adding the forwarding network | +288 | +0 |
| Adding the 2-bit branch predictor | +1071 | +136 |
| Single-cycle -> fully featured pipeline (total) | +2856 | +549 |

## Per-stage combinational depth

Each module synthesised standalone. The DEEPEST stage sets the pipelined clock period; the SUM of the five sets the single-cycle clock period.

| Module | Role | Depth (gate levels) |
|---|---|---|
| `pc_if` | IF stage | 30 |
| `decode_stage` | ID stage | 12 |
| `ex_stage` | EX stage **(deepest stage)** | 70 |
| `mem_stage` | MEM stage | 2 |
| `wb_stage` | WB stage | 1 |
| `pc_if_pred` | IF stage, predictor enabled | 56 |
| `alu` | inside EX | 67 |
| `branch_cmp` | inside EX | 10 |
| `control_unit` | inside ID | 7 |
| `imm_gen` | inside ID | 6 |
| `forwarding_unit` | hazard control | 6 |
| `hazard_unit` | hazard control | 8 |
| `branch_predictor` | BHT, read in IF | 12 |

### What the predictor costs in clock period

- Deepest stage WITHOUT the predictor: **70** (`ex_stage`)
- Deepest stage WITH the predictor: **70** (`ex_stage`)
- The predictor does NOT lengthen the critical path: the EX stage (the ALU adder) still dominates, so the extra IF logic is absorbed. The predictor is effectively free in clock period for this design.

- Sum of all five stages (single-cycle path): **115** gate levels
- Deepest single stage (pipelined path): **70** gate levels
- Implied clock-period ratio: **1.64x** shorter period when pipelined

### Honest speedup

    speedup = (T_single x cycles_single) / (T_pipe x cycles_pipe)

Using T_single / T_pipe = 1.64 and the aggregate cycle counts from results/perf.md:

| Comparison | Cycle ratio | Clock ratio | Net speedup |
|---|---|---|---|
| Single-cycle vs pipelined (pred) | 0.803x | 1.64x | **1.32x** |
| Pipelined stall-only vs forwarding | 1.421x | 1.00x (same stages) | **1.42x** |
| Forwarding vs forwarding+predictor | 1.301x | see note | **1.30x** cycles |

The predictor adds an immediate decoder and a target adder to IF, taking that stage from 30 to 56 gate levels. That is still below the EX stage at 70, so the critical path does not move and the clock ratio is unchanged: for this design the predictor's cycle saving is a genuine net win.

## Sensitivity to memory access delay

The table above excludes memory access time, which flatters the single-cycle core: its critical path contains an instruction fetch AND a data access in series, while no single pipeline stage contains both.

T_single is the single-cycle core's own path (115 levels, IF = 30); T_pipe is the `pred` configuration, whose IF stage is 56 levels deep because the predictor adds a target adder there. Writing M for the memory read delay:

    T_single  ~  IF + ID + EX + MEM + WB + 2M   =  115 + 2M
    T_pipe    ~  max(IF+M, ID, EX, MEM+M, WB)   =  max(56+M, 12, 70, 2+M, 1)

Cycle ratio is held at 0.803x, the measured single-cycle / `pred` figure.

| Memory delay M | T_single | T_pipe | Clock ratio | Critical stage | Net speedup vs single-cycle |
|---|---|---|---|---|---|
| 0 | 115 | 70 | 1.64x | EX | **1.32x** |
| 10 | 135 | 70 | 1.93x | EX | **1.55x** |
| 20 | 155 | 76 | 2.04x | IF | **1.64x** |
| 40 | 195 | 96 | 2.03x | IF | **1.63x** |
| 60 | 235 | 116 | 2.03x | IF | **1.63x** |
| 80 | 275 | 136 | 2.02x | IF | **1.62x** |

Two things to read off this table:

1. **Pipelining only pays once the stages it separates are genuinely expensive.** At M = 0 the cycle count rises by nearly as much as the clock period falls. Any realistic memory makes pipelining clearly worthwhile.
2. **Past M = 20 the critical stage moves from EX to IF**, and the clock ratio stops improving. Beyond that point the way to go faster is not to re-balance these five stages but to make memory access cheaper, or to split fetch across more stages - which is exactly why real processors have caches and why deeper pipelines break fetch and memory into several stages each.
   Note that the predictor brings this crossover forward: it deepens IF from 30 to 56 levels, so IF becomes critical at a smaller M than it would without the predictor. The predictor is free in clock period today only because the ripple-carry ALU is so deep.

## Caveats on these numbers

1. **Gate levels are not nanoseconds.** The generic library has no timing model, so a 2-input gate and a wide multiplexer count the same. These are structural comparisons.
2. **The adder dominates.** Yosys builds the 32-bit ALU adder as a ripple carry, so its carry chain is the deepest thing in the design and it sits in one stage (EX). That is why the whole-core depths of the three configurations are close together: every one of them contains the same adder. It also identifies the real bottleneck - to raise Fmax further you would replace the adder, not re-balance the stages.
3. **Memory access time is excluded.** With the memories blackboxed, the single-cycle core's path does not include an instruction fetch followed by a data access, which in reality is its largest cost. The single-cycle clock period reported here is therefore optimistic, and the real advantage of pipelining is larger than these figures show.
4. **For the FPGA deliverable**, run Vivado on this RTL to get LUT/FF utilisation and a real Fmax. Vivado maps the adder onto carry-chain primitives, which changes the balance described in point 2. Note that `dmem` has an asynchronous read and will map to distributed LUT RAM rather than block RAM - see the header comment in rtl/common/dmem.v.
