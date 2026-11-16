# Five-Stage Pipelined RISC-V Processor

**Modern Computer Architecture — Project 3**

---

## 1. Objective and scope

Design a five-stage pipelined RISC-V processor implementing a subset of
RV32I, verify it against a single-cycle reference implementation, and
measure the effect of pipelining and of operand forwarding on execution
performance.

**Implemented instruction set:** `add`, `sub`, `addi`, `lw`, `sw`, `beq`,
`bne`. `nop` is the canonical `addi x0, x0, 0`.

**Deliberately out of scope:** jumps (`jal`/`jalr`), `lui`, shifts,
logical operations, set-less-than, byte/half-word memory access,
multiply/divide, CSRs, exceptions, interrupts, privilege modes, caches,
branch prediction beyond static not-taken. Section 9 lists these as
limitations.

---

## 2. Design decisions taken before implementation

Fixing these before writing RTL is what allowed five people to work in
parallel without interface churn.

| Decision | Choice | Rationale |
|---|---|---|
| Memory model | Harvard: separate instruction and data memory | Removes the structural hazard between IF and MEM entirely. A unified memory would force a stall on every load and store. |
| Memory addressing | Word-addressed internally, byte addresses on the bus | Only aligned word accesses exist in the subset, so the low two address bits are dropped. |
| Data memory read | Combinational (asynchronous) | The MEM stage is one cycle and MEM/WB must capture the loaded word at the end of it. A registered read would arrive one cycle late. Cost: maps to distributed LUT RAM, not block RAM. See §8. |
| Branch resolution | In **EX** | 2 wasted fetch slots per taken branch instead of 3 if resolved in MEM. |
| Branch prediction | Static not-taken, **or** a 2-bit branch history table (parameter) | Static is the baseline; the dynamic predictor is §7.8 and the measurements in §6 cover both. |
| Hazard strategy | Forwarding + 1-cycle load-use stall | The project asks for dependent instruction sequences; forwarding is what makes them cheap. |
| Register file | 2 combinational read ports, 1 synchronous write port, `x0` hardwired to 0, internal write-to-read bypass | The bypass removes the WB→ID hazard so the forwarding network only needs two sources. |
| Control signal handling | Generated once in ID, carried in the pipeline registers | Recomputing control in a later stage applies it to the wrong instruction — the single most common pipelining bug. |
| Reset | Synchronous, active high, PC → 0 | Uniform across all modules. |
| Program termination | Fetching the word `0x00000000` halts fetch | `0x00000000` is not a legal RISC-V instruction. Lets the testbench count retired instructions exactly without knowing the program length. Simulation-only convention. |

### 2.1 Three configurations

| Name | How it is built | Role |
|---|---|---|
| `single` | `rtl/single_cycle/riscv_single_cycle.v` | Golden model. CPI = 1.000 by construction. |
| `stall` | `FORWARD_EN = 0`, `PREDICTOR = 0` | No bypass paths; ID waits for the producer to reach WB. |
| `fwd` | `FORWARD_EN = 1`, `PREDICTOR = 0` | Full forwarding; stalls only on load-use. Static not-taken branches. |
| `pred` | `FORWARD_EN = 1`, `PREDICTOR = 1` | Adds a 64-entry table of 2-bit saturating counters. |

The three pipelined configurations come from **the same RTL**, differing
only by parameters, and each step changes exactly one feature. Any
difference in measured CPI or synthesised area is therefore attributable
to that one feature:

```
stall  --[+ forwarding network]-->  fwd  --[+ 2-bit predictor]-->  pred
```

---

## 3. Datapath and stage partitioning

```
      IF              ID              EX             MEM            WB
 +----------+    +-----------+    +---------+    +---------+   +--------+
 |  pc_if   |    | decode_   |    | ex_     |    | mem_    |   | wb_    |
 |  PC      |    | stage     |    | stage   |    | stage   |   | stage  |
 |  imem    |    | regfile   |    | fwd mux |    | dmem    |   | WB mux |
 |  +4 / tgt|    | imm_gen   |    | ALU     |    |         |   |        |
 |          |    | control   |    | br cmp  |    |         |   |        |
 +----------+    +-----------+    +---------+    +---------+   +--------+
       |   IF/ID       |   ID/EX      |  EX/MEM      | MEM/WB     |
       +-------->[R]---+------>[R]----+----->[R]-----+---->[R]----+
                                                                  |
             write port of the register file  <--------------------+
```

### 3.1 Pipeline register contents

| Register | Data fields | Control fields |
|---|---|---|
| IF/ID | `pc`, `instr`, `valid`, `predicted_taken` | — |
| ID/EX | `pc`, `rs1_data`, `rs2_data`, `imm`, `rs1_addr`, `rs2_addr`, `rd_addr`, `instr`, `valid`, `predicted_taken` | `reg_write`, `alu_src`, `alu_ctrl[1:0]`, `mem_read`, `mem_write`, `mem_to_reg`, `branch`, `branch_ne` |
| EX/MEM | `alu_result`, `store_data`, `rd_addr`, `instr`, `valid` | `reg_write`, `mem_read`, `mem_write`, `mem_to_reg` |
| MEM/WB | `alu_result`, `mem_data`, `rd_addr`, `instr`, `valid` | `reg_write`, `mem_to_reg` |

Two deliberate choices in this table:

- **Control fields narrow as they travel.** Once EX has consumed
  `alu_src`, `alu_ctrl`, `branch` and `branch_ne`, they are not
  propagated. Carrying a signal past the stage that needs it only invites
  a later stage to misuse it.
- **MEM/WB carries both `alu_result` and `mem_data`** rather than a single
  pre-muxed `wb_data`. This costs 32 flip-flops but means the MEM/WB
  forwarding path can select exactly the value WB will write, using the
  same `mem_to_reg` bit, with no duplicated mux. It also makes a
  mis-selected write-back source visible in a waveform instead of subtle.

- `instr` is carried in every register for tracing and debug only. It is
  free in simulation; on an FPGA it would be removed for production.
- `predicted_taken` travels with the instruction it belongs to, so it is
  still correct after a stall. EX needs it to decide whether the
  prediction was right (§4.6). It exists only in the `PREDICTOR = 1`
  build; with static prediction it is a constant and synthesis removes
  it.

### 3.2 The `valid` bit

Every pipeline register carries a `valid` bit distinguishing a real
instruction from a bubble. It is used for:

- counting retired instructions (`retire_valid` = MEM/WB `valid`),
- preventing the hazard unit from reacting to an empty slot,
- gating `mem_write` in MEM and `reg_write` in WB as a safety belt.

---

## 4. Hazard analysis

### 4.1 Which hazards can occur

| Hazard class | Present? | Why |
|---|---|---|
| RAW (read after write) | **Yes** | The main problem this design solves. |
| WAR (write after read) | No | In-order issue, and every instruction reads its registers in ID before any later instruction can write in WB. |
| WAW (write after write) | No | One architectural write per instruction, all writes in WB, in order, through a single write port. |
| Structural | No | Separate instruction and data memories; the register file has two read ports and one write port, which is exactly what one instruction needs. |
| Control | **Yes** | Conditional branches resolve in EX, two cycles after fetch. |

### 4.2 RAW hazards with forwarding (`FORWARD_EN = 1`)

A result produced by the ALU exists at the end of EX, and the consumer
needs it at the start of its own EX. Two bypass paths cover every
distance:

| Producer position relative to consumer | Path | Penalty |
|---|---|---|
| Distance 1 (in EX/MEM) | EX/MEM → EX | 0 |
| Distance 2 (in MEM/WB) | MEM/WB → EX | 0 |
| Distance 3+ | none needed — the register file's internal write-to-read bypass has already made the value visible to the ID read ports | 0 |

**Forwarding priority.** If both EX/MEM and MEM/WB are writing the same
register, the correct source is EX/MEM, because that is the *younger*
instruction and its write happens later in program order. Checking MEM/WB
first forwards a stale value. Verified by group 3 of the directed test.

**`rd == x0` is excluded from forwarding.** Writes to `x0` are discarded
by the register file, so forwarding one would deliver a value that is
never architecturally visible. Verified by group 4.

### 4.3 The load-use hazard — the one forwarding cannot remove

```
cycle:          1    2    3    4    5    6
lw   x1,0(x2)   IF   ID   EX   MEM  WB
add  x3,x1,x4        IF   ID   EX   MEM  WB
                                ^
                   needs x1 at the start of cycle 4,
                   but memory only returns it during cycle 4
```

Time does not run backwards, so one bubble is unavoidable:

```
cycle:          1    2    3    4    5    6    7
lw   x1,0(x2)   IF   ID   EX   MEM  WB
add  x3,x1,x4        IF   ID   **   EX   MEM  WB
                                |    ^
                             bubble  x1 forwarded MEM/WB -> EX
```

Detection condition: a load is in EX, it writes a non-zero register, and
the instruction in ID actually reads that register.

The qualifier *actually reads* matters. For `addi` and `lw` the
`instr[24:20]` field is part of the immediate, not an `rs2` register
number. Without the `uses_rs1` / `uses_rs2` signals from the control
unit, the hazard detector would stall on a register number that is really
immediate bits — a false dependency that silently inflates CPI.

### 4.4 RAW hazards without forwarding (`FORWARD_EN = 0`)

With no bypass paths, a value is readable only once it is in the register
file. Because the register file has an internal write-to-read bypass, ID
can read a value being written by an instruction in WB in the same cycle.
So ID must wait for a producer in EX or MEM, but not for one in WB:

```
add x1,x2,x3   IF   ID   EX   MEM  WB
add x4,x1,x5        IF   ID   **   **   EX   MEM  WB
                                |    |   ^
                      producer in    in  producer in WB,
                           EX       MEM  regfile bypass supplies x1
```

A distance-1 dependency costs **2** bubbles, distance-2 costs **1**, and a
load-use pair also costs 2. This is the gap measured in §6.

### 4.5 Control hazards

A branch is fetched in cycle *k* and resolves in EX in cycle *k+2*. By
then two more instructions have been fetched. On a taken branch both are
discarded: IF/ID is cleared and ID/EX receives a bubble, while the PC
loads the branch target.

**Flush takes priority over stall.** A stalled instruction on a
mispredicted path must still be discarded.

**A bubble clears every control bit, not just `valid`.** This is the most
important single line in the hazard design. `reg_write`, `mem_write`,
`mem_read` and `branch` must all go to zero, otherwise a flushed `sw`
writes memory. Group 10 of the directed test exists specifically to catch
this: it places a `sw` in a flushed slot and asserts the target memory
word is still zero.

Branch operands are taken from **after** the forwarding muxes, so a branch
can compare a value produced by the instruction immediately before it
(group 9).

### 4.6 Dynamic branch prediction (`PREDICTOR = 1`)

Static not-taken is wrong on every taken branch, and §6.3 shows taken
branches to be the largest single source of lost cycles. The `pred`
configuration adds a **branch history table**: 64 entries of 2-bit
saturating counter, indexed by `PC[7:2]`, read in IF and updated in EX.

```
     taken ->          taken ->         taken ->
  00 ----------> 01 ----------> 10 ----------> 11
 strong <------- weak  <------- weak  <------- strong
   NT   not taken NT  not taken  T   not taken   T
```

The prediction is the counter's top bit. Two bits rather than one because
a single bit mispredicts twice per loop: once on the final, not-taken
iteration, and then again on the first iteration of the next entry into
the loop, because that final iteration flipped the bit. A 2-bit counter
absorbs one anomalous outcome without changing its prediction.

All entries reset to `01` (weakly not taken), so the **first** prediction
for any branch is identical to what the static configuration would do.
The comparison between `fwd` and `pred` therefore isolates the effect of
learning and nothing else.

**No branch target buffer is needed.** A predictor normally needs one,
because at fetch time the instruction has not been decoded. Here the
instruction memory read is combinational, so `instr` is already available
in IF: the opcode identifies a branch and a B-format immediate decoder
plus one adder give the target directly. The cost is that IF now contains
an adder it did not before — quantified in §7.8.

**Checking the prediction in EX.** The outcome is compared with the
prediction that travelled down the pipeline alongside the instruction:

| Predicted | Actual | Outcome |
|---|---|---|
| 0 | 0 | correct — nothing happens |
| 0 | 1 | mispredicted not-taken → redirect to `pc + imm` |
| 1 | 0 | mispredicted taken → redirect to `pc + 4` |
| 1 | 1 | **correct — no flush, the target was already fetched** |

The third row is new. Static not-taken can only ever be wrong in one
direction, so it only ever needs the branch target. A predictor that can
say "taken" can also be wrong about that, and must then recover to the
fall-through path — so the redirect target is a multiplexer, not just the
branch target adder.

The fourth row is where the performance comes from: a correctly predicted
taken branch costs **nothing at all**.

**Aliasing.** There is no tag, so two branches whose addresses differ only
in bits above `PC[7]` share an entry. A wrong prediction is only a
performance loss, never a correctness problem, because EX always checks
the real outcome. At 64 entries the table covers 256 bytes of code, more
than any benchmark here, so no aliasing occurs in these measurements —
stated as a limitation rather than claimed as a result.

---

## 5. Verification

Correctness is established by three independent mechanisms.

### 5.1 Unit tests

`tb_alu.v` — add, sub, negative results, two's complement wraparound,
zero flag.

`tb_regfile.v` — the two properties the pipeline depends on: `x0` reads as
zero and discards writes; the same-cycle write-to-read bypass works, does
not fire when the write enable is low, and does not fire for `x0`.

### 5.2 Directed hazard test — 34 assertions

`tb_hazards.v` runs `programs/hazard_suite.s` and checks every
architectural register and the relevant memory words against hardcoded
expected values. One group per hazard class, each failing loudly and
naming the mechanism it tests:

| Group | Tests |
|---|---|
| 1 | distance-1 and distance-2 RAW on ALU results |
| 2 | MEM/WB → EX path in isolation |
| 3 | forwarding priority — younger producer must win |
| 4 | `rd == x0` must never be forwarded |
| 5 | load-use stall |
| 6 | store data forwarding (rs2 mux placement) |
| 7 | branch not taken — fall-through executes |
| 8 | branch taken — both following slots flushed |
| 9 | branch operand forwarded into the comparator |
| 10 | a flushed store must not reach memory |

The expected values are *architectural*, so the same 34 assertions pass on
all three configurations regardless of how many bubbles each needs.

**Result: 34/34 pass on all four configurations** — `single`, `stall`,
`fwd` and `pred`.

Note that `hazard_suite` takes the same 45 cycles on `fwd` and `pred`.
Every branch in it executes exactly once, so the predictor is always cold
and always predicts not-taken: identical behaviour to static. That is the
expected result, and it is a useful negative control — a predictor that
somehow "helped" on single-execution branches would indicate a bug.

### 5.3 Golden-model comparison

For every benchmark, each core writes an architectural signature — `x1`
through `x31` and `dmem[0..31]`. The two pipelined signatures must match
the single-cycle signature byte for byte.

**Result: 21/21 signature comparisons match** (7 benchmarks x 3 pipelined
configurations).

This is the check that actually proves the pipeline correct. Cycle counts
only prove it is fast.

### 5.4 Cycle accounting as a verification check

For every pipelined run the testbench verifies:

```
cycles  ==  instructions + 4 (fill) + stall_cycles + 2 x mispredictions
```

Note that the last term is **mispredictions**, not taken branches. For the
static configurations the two are the same number, because a not-taken
policy mispredicts exactly the taken branches. For `pred` they diverge,
and the divergence is the whole benefit of the feature.

**This holds exactly for all 21 pipelined runs.** It is a strong check:
any unexplained cycle would mean a stall or flush the design is taking but
not reporting, and any missing cycle would mean a counter is wrong.

### 5.5 Two bugs found during bring-up

Both are documented because the evaluation criteria ask about verification
quality, and both were found by the infrastructure rather than by
inspection.

**Bug 1 — combinational loop in the single-cycle core.**
The register file's write-to-read bypass is essential in the pipeline,
where the write comes from an *older* instruction in WB. In the
single-cycle core the read and the write belong to the *same* instruction,
so the bypass closes a loop:

```
rs1_data -> ALU -> wb_data -> (bypass) -> rs1_data
```

Any instruction whose `rd` equals one of its own sources triggers it. The
first three benchmarks passed because none of them reuses a destination as
a source; `array_sum.s` (`add x2, x2, x4`) was the first program to hang
the simulator. Fixed by making the bypass a parameter, `WB_BYPASS`, set to
0 for the single-cycle core and 1 for the pipeline. Worth stating plainly:
two cores cannot simply share every submodule unchanged.

**Bug 2 — reset deassertion race in the testbench.**
Releasing reset with a blocking assignment immediately after a `posedge`
races the counter and trace `always` blocks, which sample `rst` at that
same edge. Whether they saw 1 or 0 depended on procedural ordering within
the time step, making the cycle count non-deterministic by ±1 — enough to
corrupt every CPI figure. Fixed by releasing reset on a `negedge`. The
discrepancy was noticed because the pipeline trace and the cycle counter
disagreed by one; they now share a single counter, so they agree by
construction.

---

## 6. Performance results

Seven benchmarks, 523 instructions in total.

### 6.1 CPI by benchmark

| Benchmark | Instrs | Single-cycle | Stall only | Forwarding | Fwd + predictor | Forwarding gain | Predictor gain |
|---|---|---|---|---|---|---|---|
| `independent` | 16 | 1.000 | 1.250 | 1.250 | 1.250 | 1.00x | 1.00x |
| `dep_chain` | 16 | 1.000 | 3.125 | 1.250 | 1.250 | 2.50x | 1.00x |
| `load_use` | 13 | 1.000 | 2.077 | 1.615 | 1.615 | 1.29x | 1.00x |
| `array_sum` | 68 | 1.000 | 2.441 | 1.735 | 1.353 | 1.41x | 1.28x |
| `branch_mix` | 45 | 1.000 | 1.956 | 1.489 | 1.178 | 1.31x | 1.26x |
| `fib` | 105 | 1.000 | 1.971 | 1.400 | 1.076 | 1.41x | 1.30x |
| `vecsum64` | 260 | 1.000 | 2.485 | 1.746 | 1.277 | 1.42x | 1.37x |

### 6.2 Aggregate

| Configuration | Instrs | Cycles | CPI | IPC | Cycles saved |
|---|---|---|---|---|---|
| Single-cycle | 523 | 523 | 1.000 | 1.000 | — |
| Pipelined, stall-only | 523 | 1204 | 2.302 | 0.434 | — |
| Pipelined, forwarding | 523 | 847 | 1.620 | 0.617 | **357 (1.42x)** |
| Pipelined, fwd + predictor | 523 | 651 | 1.245 | 0.803 | **196 (1.30x)** |

The two features together remove **553 of the 681** hazard cycles that the
naive pipeline paid — 81% of the overhead.

### 6.3 Branch prediction accuracy

| Benchmark | Branches | Taken | Static NT mispredicts | Static accuracy | 2-bit BHT mispredicts | BHT accuracy |
|---|---|---|---|---|---|---|
| `array_sum` | 16 | 15 | 15 | 6.2% | 2 | 87.5% |
| `branch_mix` | 20 | 9 | 9 | 55.0% | 2 | 90.0% |
| `fib` | 20 | 19 | 19 | 5.0% | 2 | 90.0% |
| `vecsum64` | 64 | 63 | 63 | 1.6% | 2 | 96.9% |
| **total** | **120** | **106** | **106** | **11.7%** | **8** | **93.3%** |

Accuracy rises from **11.7% to 93.3%**, removing 98 of 106
mispredictions and 196 cycles of flushed work.

**The predictor misses exactly twice per loop, on every benchmark.** This
is not a coincidence and it is worth stating, because it shows the
hardware behaving exactly as the theory predicts:

1. **Loop entry.** The counter starts at `01` (weakly not taken), so the
   first iteration is mispredicted. The counter moves to `10`.
2. **Steady state.** Every subsequent iteration is predicted taken and is
   correct. The counter saturates at `11`.
3. **Loop exit.** The final iteration is not taken, so it is
   mispredicted. The counter drops back to `10` — still predicting taken,
   which is why re-entering the same loop later would cost nothing.

`vecsum64` runs its loop 64 times and mispredicts twice: 96.9% accuracy,
which is the asymptotic result for a counted loop. `branch_mix` starts
from a higher static baseline (55%) because half its branches are
genuinely not-taken, and still reaches 90%.

### 6.4 Reading these numbers correctly

**(a) The predictor does nothing on `independent`, `dep_chain` and
`load_use` — and it should not.** Those three contain no branches at all,
so the columns are identical to `fwd`. This confirms the predictor adds no
cost when there is nothing to predict, and it is a useful control: any
change in those three numbers would mean the predictor was interfering
with something it should not touch.

**(b) `independent` is identical in all three pipelined configurations
(CPI 1.250).** No dependencies and no branches, so neither feature has
anything to do. Its CPI is above 1.0 purely because of the 4-cycle
pipeline fill: 16 instructions in 20 cycles.

**(c) `dep_chain` is the synthetic extreme for forwarding (2.50x).** Every
instruction consumes the previous result, so stall-only pays 2 bubbles per
instruction (CPI 3.125 ≈ 1 + 2) while forwarding pays none (CPI 1.250,
identical to `independent` — every hazard eliminated).

**(d) `fib` is the most striking result: CPI 1.076.** A dependency-dense
loop with no memory traffic in the body. Forwarding eliminates every data
hazard and the predictor eliminates almost every control hazard, leaving
105 instructions in 113 cycles — within 7% of the ideal CPI of 1.0 for a
scalar pipeline. The residual 8 cycles are the 4-cycle fill and 2
mispredictions.

**(e) Short benchmarks flatter the pipeline; quote `vecsum64`.** The
4-cycle fill is 25% of `independent`'s cycles but only 1.5% of
`vecsum64`'s. Its steady-state CPI decomposes cleanly:

```
per iteration (4 instructions: lw, add, addi, bne)
  static not-taken              with the 2-bit predictor
  4  useful work                4  useful work
+ 1  load-use bubble          + 1  load-use bubble
+ 2  branch flush             + 0  branch correctly predicted
= 7 cycles / 4 instrs         = 5 cycles / 4 instrs
  CPI 1.75  (measured 1.746)    CPI 1.25  (measured 1.277)
```

With static prediction the branch penalty is **two thirds** of the
overhead and the load-use bubble one third. The predictor removes almost
all of the larger share, which is why it was the right feature to add
next, and why what remains is now dominated by the load-use bubble —
making a load-use-aware scheduler or a deeper bypass the logical next
step rather than a better predictor.

### 6.5 Why the pipelined core still uses more cycles than the single-cycle core

The single-cycle core has CPI = 1.000 by definition. Even the best
pipelined configuration has CPI = 1.245. **Cycle count alone therefore
still says pipelining made things worse.**

It did not, because the two cores cannot run at the same clock frequency.
The single-cycle core's clock period must cover IF + ID + EX + MEM + WB in
series; the pipelined core's need only cover the slowest single stage. The
honest comparison is:

```
speedup = (T_single x cycles_single) / (T_pipe x cycles_pipe)
```

Section 7 supplies the clock-period ratio. Note that the predictor
improves the cycle side of this product from 0.617x to 0.803x, so it moves
the pipelined design from break-even to a clear win.

---

## 7. Synthesis results

Yosys, generic gate library, memories blackboxed (on an FPGA they map to
block RAM, not fabric logic; the 32x32 register file *is* included, which
is why all flip-flop counts start near 1024).

### 7.1 Area

| Configuration | Total cells | Flip-flops | Multiplexers | Whole-core depth |
|---|---|---|---|---|
| Single-cycle | 4431 | 1056 | 1891 | 78 |
| Pipelined, stall-only | 5928 | 1469 | 1519 | 68 |
| Pipelined, forwarding | 6216 | 1469 | 1563 | 77 |
| Pipelined, fwd + predictor | 7287 | 1605 | 1638 | 79 |

The single-cycle core's 1056 flip-flops are exactly the architectural
state: 32 registers x 32 bits = 1024, plus the 32-bit PC. Everything above
that is pipelining.

### 7.2 What each feature costs

| Change | Extra cells | Extra flip-flops |
|---|---|---|
| Single-cycle → pipelined (4 pipeline registers + hazard unit) | +1497 | +413 |
| Adding the forwarding network | **+288** | **+0** |
| Adding the 2-bit branch predictor | +1071 | +136 |
| Total | +2856 | +549 |

Two observations worth making:

**The forwarding network is the best value in the design: 288 gates, zero
flip-flops, for a 1.42x cycle-count speedup.** It is pure combinational
logic — two 3-input multiplexers and the comparators that drive them — so
it adds no state at all.

**The predictor's +136 flip-flops are almost entirely the table itself.**
64 entries x 2 bits = 128, plus one `predicted_taken` bit in each of IF/ID
and ID/EX, plus 6 cells of control. The synthesised flip-flop types
confirm the reset state directly: 64 flops reset to 0 and 64 reset to 1,
which is the bit pattern `01` — weakly not taken, as specified in §4.6.

### 7.3 Per-stage combinational depth

| Module | Role | Depth (gate levels) |
|---|---|---|
| `pc_if` | IF, static prediction | 30 |
| `pc_if` | IF, **predictor enabled** | **56** |
| `decode_stage` | ID | 12 |
| `ex_stage` | **EX — deepest** | **70** |
| `mem_stage` | MEM | 2 |
| `wb_stage` | WB | 1 |
| `alu` | inside EX | 67 |
| `branch_cmp` | inside EX | 10 |
| `control_unit` | inside ID | 7 |
| `imm_gen` | inside ID | 6 |
| `forwarding_unit` | hazard control | 6 |
| `hazard_unit` | hazard control | 8 |
| `branch_predictor` | BHT, read in IF | 12 |

- Sum of all five stages (the single-cycle path): **115**
- Deepest single stage (the pipelined path): **70**
- Implied clock-period ratio: **1.64x**

**The EX stage dominates, and within it the ALU (67 of 70 levels).** Yosys
builds the 32-bit adder as a ripple carry, so its carry chain is the
deepest thing in the design. This identifies the real bottleneck: to go
faster you would replace the adder with a carry-lookahead or carry-select
structure, *not* re-balance the five stages. The stages are also badly
unbalanced — 70 against 1 for WB — which is inherent to this
partitioning, since write-back is a single multiplexer.

### 7.4 What the predictor costs in clock period

This is the measurement that decides whether the predictor is actually
worth it, and it has to be made rather than assumed.

| | Without predictor | With predictor |
|---|---|---|
| IF stage depth | 30 | **56** |
| Deepest stage | 70 (`ex_stage`) | 70 (`ex_stage`) |

The predictor nearly doubles the depth of IF, from 30 to 56 gate levels,
because that stage now contains a B-format immediate decoder and a 32-bit
target adder that it did not before. **But 56 is still below the EX
stage's 70, so the critical path does not move and the clock period is
unchanged.** For this design the predictor's cycle saving is a genuine net
win.

That conclusion is contingent, and the report should say so: the predictor
is free *only because* the ripple-carry ALU is so deep. On an FPGA, where
Vivado maps the adder onto carry-chain primitives, EX will shrink
substantially and **IF may well become the critical path**. If that
happens, the fix is to move the target adder into its own stage or to
precompute targets — not to abandon the predictor, whose cycle benefit is
large.

### 7.5 Net speedup

| Comparison | Cycle ratio | Clock ratio | Net speedup |
|---|---|---|---|
| Single-cycle vs pipelined (stall only) | 0.434x | 1.64x | 0.71x |
| Single-cycle vs pipelined (forwarding) | 0.617x | 1.64x | 1.01x |
| Single-cycle vs pipelined (fwd + predictor) | 0.803x | 1.64x | **1.32x** |
| Stall-only vs forwarding | 1.421x | 1.00x | **1.42x** |
| Forwarding vs fwd + predictor | 1.301x | 1.00x | **1.30x** |

This table is the clearest single summary of the project. Read down the
first three rows: the naive pipeline is **slower** than the single-cycle
core (0.71x), forwarding brings it to break-even (1.01x), and the
predictor makes it a real improvement (1.32x). **Pipelining on its own is
not a performance win — pipelining plus hazard mitigation is.** That is
the central result.

### 7.6 Sensitivity to memory access delay

Blackboxing the memories removes memory access time from *both* cores, but
it helps the single-cycle core far more, because its critical path
contains an instruction fetch **and** a data access in series while no
single pipeline stage contains both. Writing M for the memory read delay
in gate levels, with T_single from the single-cycle core's own stages
(IF = 30, since it has no predictor) and T_pipe from the `pred`
configuration (IF = 56):

```
T_single  ~  115 + 2M
T_pipe    ~  max(56+M, 12, 70, 2+M, 1)
```

| Memory delay M | T_single | T_pipe | Clock ratio | Critical stage | Net speedup |
|---|---|---|---|---|---|
| 0 | 115 | 70 | 1.64x | EX | 1.32x |
| 10 | 135 | 70 | 1.93x | EX | 1.55x |
| 20 | 155 | 76 | 2.04x | IF | **1.64x** |
| 40 | 195 | 96 | 2.03x | IF | 1.63x |
| 60 | 235 | 116 | 2.03x | IF | 1.63x |
| 80 | 275 | 136 | 2.02x | IF | 1.62x |

1. **Any realistic memory makes pipelining clearly worthwhile.** At M = 0
   the cycle count rises by nearly as much as the clock period falls; by
   M = 20 the net speedup is 1.64x.
2. **Past M = 20 the critical stage moves from EX to IF and the clock
   ratio stops improving.** Beyond that point the way to go faster is not
   to re-balance these five stages but to make memory access cheaper or
   split fetch across more stages — which is exactly why real processors
   have caches and why deeper pipelines break fetch and memory into
   several stages each.
3. **The predictor brings that crossover forward**, because it deepens IF
   from 30 to 56 levels. Without it, IF would not become critical until
   M ≈ 40. This is the clearest quantitative statement of the predictor's
   true cost: not area, not cycles, but how much earlier it makes fetch
   the bottleneck.

### 7.7 Caveats

1. **Gate levels are not nanoseconds.** The generic library has no timing
   model; a 2-input gate and a wide multiplexer count the same. These are
   structural comparisons.
2. **Ripple-carry adder.** Vivado maps the adder onto dedicated
   carry-chain primitives, which changes §7.3 and §7.4 substantially.
3. **FPGA figures still to be collected.** `docs/VIVADO.md` has the steps.
   Note that `dmem` has an asynchronous read and will map to distributed
   LUT RAM rather than block RAM.

---

## 8. Pipeline timing evidence

`results/trace_*.txt` contain cycle-by-cycle stage occupancy traces;
`results/*.vcd` are the matching waveforms for GTKWave.

### 8.1 Instruction overlap (`independent`, forwarding)

Five instructions in flight simultaneously from cycle 5 onwards; 16
instructions complete in 20 cycles rather than 80.

### 8.2 Load-use bubble (`load_use`, forwarding)

```
cyc | IF pc | ID        | EX        | MEM       | WB        | event
  4 |     8 | lw        | addi      |   --      |   --      |
  5 |    12 | add       | lw        | addi      |   --      | STALL (bubble into EX)
  6 |    12 | add       |   --      | lw        | addi      |
  7 |    16 | lw        | add       |   --      | lw        |
```

At cycle 5 the `add` needs the `lw` result; the hazard unit holds IF and
IF/ID (the PC stays at 12) and injects a bubble, visible as `--` in EX at
cycle 6. The `add` then proceeds and receives the value by MEM/WB → EX
forwarding.

### 8.3 Branch flush (`branch_mix`, forwarding)

```
cyc | IF pc | ID        | EX        | MEM       | WB        | event
  9 |    32 | bne       | addi      | beq       | addi      |
 10 |    36 | sw        | bne       | addi      | beq       | BRANCH TAKEN -> flush IF/ID and ID/EX
 11 |    16 |   --      |   --      | bne       | addi      |
 12 |    20 | addi      |   --      |   --      | bne       |
```

At cycle 10 the `bne` is in EX and resolves taken. The `sw` in IF/ID and
the instruction entering ID/EX are both discarded — the two `--` entries
at cycle 11 — and the PC jumps from 36 back to the loop target at 16.
Exactly the 2-cycle penalty predicted in §4.5.

### 8.4 Forwarding versus stalling (`dep_chain`)

Compare `results/trace_dep_chain_stall.txt` (50 cycles, 30 stall cycles)
with `results/trace_dep_chain_fwd.txt` (20 cycles, 0 stall cycles) — the
same 16 instructions.

### 8.5 The predictor eliminating the branch penalty (`array_sum`)

The clearest single piece of evidence in the project: the same loop, the
same four instructions, with and without the predictor.

**Static not-taken** — 7 cycles per iteration
(`results/trace_array_sum_fwd.txt`):

```
cyc | IF pc | ID        | EX        | MEM       | WB        | event
 16 |    28 | bne       | addi      | add       |   --      |
 17 |    32 | sw        | bne       | addi      | add       | MISPREDICT -> flush IF/ID and ID/EX
 18 |    12 |   --      |   --      | bne       | addi      |
 19 |    16 | lw        |   --      |   --      | bne       |
 20 |    20 | add       | lw        |   --      |   --      | STALL (bubble into EX)
 21 |    20 | add       |   --      | lw        |   --      |
 22 |    24 | addi      | add       |   --      | lw        |
 23 |    28 | bne       | addi      | add       |   --      |   <- next iteration, 7 cycles later
```

IF fetches PC 32 (the `sw` after the loop) every single iteration, and
every single iteration it is thrown away. Cycles 18 and 19 show the two
dead slots.

**With the 2-bit predictor** — 5 cycles per iteration
(`results/trace_array_sum_pred.txt`):

```
cyc | IF pc | ID        | EX        | MEM       | WB        | event
 16 |    12 | bne       | addi      | add       |   --      |
 17 |    16 | lw        | bne       | addi      | add       |
 18 |    20 | add       | lw        | bne       | addi      | STALL (bubble into EX)
 19 |    20 | add       |   --      | lw        | bne       |
 20 |    24 | addi      | add       |   --      | lw        |
 21 |    12 | bne       | addi      | add       |   --      |   <- next iteration, 5 cycles later
```

Two things to point at:

1. **There is no MISPREDICT event and there are no dead slots.** The
   pipeline stays full across the backward branch.
2. **IF never fetches PC 32 at all.** At cycle 20 the PC goes straight
   from 24 to 12, the loop target — the predictor redirected fetch two
   cycles before EX confirmed the branch. The wrong-path instruction is
   never fetched, rather than being fetched and discarded.

The only remaining bubble is the load-use stall at cycle 18, which is
exactly what §6.4(e) predicts: 5 cycles per 4 instructions, CPI 1.25.

---

## 9. Limitations

1. **Instruction set.** Seven instructions. No jumps, so no function
   calls; no `lui`, so no large constants; no shifts or logical ops; no
   `slt`, so no magnitude comparison — which is why no sorting benchmark
   is included.
2. **No exceptions, interrupts or privilege modes.**
3. **No caches.** Both memories are single-cycle and ideal.
4. **Branch prediction is direction-only, with no target buffer and no
   tag.** The 64-entry table has no tags, so branches more than 256 bytes
   apart can alias (§4.6); no benchmark here is large enough to trigger
   it, so the effect is unmeasured. There is no return address stack,
   because there are no calls. A correlating (two-level) predictor would
   help on branches whose behaviour depends on other branches, of which
   these benchmarks have none.
5. **The load-use bubble is now the dominant remaining overhead.** With
   the predictor handling control hazards, §6.4(e) shows the load-use
   stall is what is left. Compiler scheduling to fill the slot, or a
   deeper bypass, is the logical next step — not a better predictor.
6. **Asynchronous data memory read** prevents block RAM inference (§2).
7. **Simulation-only halt convention** (`0x00000000`). Real code would use
   an ECALL or an infinite loop.
8. **Unbalanced stages** (70 vs 1 gate levels) — inherent to the classic
   five-stage split, not a defect, but it bounds achievable Fmax. The
   predictor makes IF the second-deepest stage (56), so the imbalance is
   less extreme than before but the EX adder still sets the period.
9. **`instr` carried in every pipeline register** for tracing. Free in
   simulation; would be stripped for a production build.

---

## 10. Reproducing every number in this report

```bash
./sim/run_all.sh     # §5, §6, §8  -> results/perf.md, results/trace_*.txt
./sim/synth.sh       # §7          -> results/synth_summary.md
```

Both scripts return a non-zero exit status if any check fails.

| Section | Generated artefact |
|---|---|
| §5.2, §5.3, §5.4 | `results/run.log` |
| §6 | `results/perf.csv`, `results/perf.md` |
| §7 | `results/synth_*.txt`, `results/depths.txt`, `results/synth_summary.md` |
| §8 | `results/trace_*.txt`, `results/*.vcd` |

To reproduce one configuration on one benchmark with a trace:

```bash
./sim/run.sh pred array_sum +trace
```

Valid configurations are `single`, `stall`, `fwd` and `pred`.
