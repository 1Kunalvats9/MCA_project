# Video submission script — 3 presenters

Target length **12 minutes**, roughly 4 minutes each. Trim/expand markers
are noted in each part. Everything here can be run **live**: the full
regression takes 1.2 seconds and a single trace 0.06 seconds.

---

## Role split for 3 people

The RTL header comments and the README role table describe a five-way
split (Members A–E). With three presenters those collapse as follows, and
each person speaks only about their own group:

| Presenter | Covers | Files |
|---|---|---|
| **P1** | Front end + Decode (A+B) | `pc_if.v`, `if_id.v`, `imem.v`, `branch_predictor.v`, `decode_stage.v`, `id_ex.v`, `regfile.v`, `imm_gen.v`, `control_unit.v` |
| **Kunal** | Execute + Back end (C+D) | `ex_stage.v`, `alu.v`, `branch_cmp.v`, `forwarding_unit.v`, `ex_mem.v`, `mem_stage.v`, `mem_wb.v`, `wb_stage.v`, `dmem.v`, `hazard_unit.v` |
| **P2** | Verification + Performance (E) | `tb_*.v`, `asm.py`, `perf_table.py`, `synth_table.py`, `fpga_table.py`, `sim/*.sh`, `fpga/` |

Kunal takes hazards end to end — forwarding *and* stalling *and* the
prediction correction — because they are one coherent story and splitting
them makes the middle of the video confusing.

---

## Before you record (10 minutes, once)

Run these so `results/` is populated and nothing has to be generated on
camera:

```bash
cd /Users/kunalvats/Downloads/Coding/MCA_project && ./sim/run_all.sh && ./sim/synth.sh
```

Then:

- **Terminal font size up** to ~16–18pt. The traces are 70 columns wide;
  make sure a full trace line fits without wrapping.
- **Window width** at least 100 columns, or the trace tables will wrap and
  become unreadable on video.
- Open these in an editor, in tabs, in this order so nobody hunts for a
  file on camera: `rtl/pipelined/riscv_pipeline.v`,
  `rtl/pipelined/hazard_unit.v`, `rtl/pipelined/forwarding_unit.v`,
  `results/perf.md`, `results/synth_summary.md`.
- Each person should **run their own commands once** before recording, so
  the output on screen is familiar.
- `clear` between sections.

**Do not run `./sim/synth.sh` live** — it takes 12 seconds, which is a
long silence on camera. Show `results/synth_summary.md` instead.

**If a command fails on camera:** don't debug on video. Say "I'll come
back to that", carry on, and re-record that take. All commands are
deterministic, so a failure means a typo or wrong directory.

---

# PART 1 — P1: Design and architecture (~4 min)

### Opening (~25 s)

> [ON SCREEN: `README.md`]
>
> "Hi, we're presenting Project 3, a five-stage pipelined RISC-V
> processor. I'm [name], this is [Kunal] and [name].
>
> We implemented an RV32I subset — add, sub, addi, lw, sw, beq and bne —
> in Verilog. But the thing I'd point out first is that we didn't build
> one processor. We built **four**, and that's deliberate.
>
> There's a single-cycle core that acts as our correctness reference. Then
> a pipelined core in three configurations: one with no hazard handling at
> all, one with operand forwarding, and one that adds a branch predictor.
> The three pipelined ones are the **same RTL** — they differ only by
> parameters. So every number we show you isolates exactly one feature."

### The five stages (~90 s)

> [ON SCREEN: the stage diagram in `docs/REPORT.md` §3, or `riscv_pipeline.v`]
>
> "The datapath splits into the classic five stages. Fetch, decode,
> execute, memory, write-back — and four pipeline registers between them:
> IF/ID, ID/EX, EX/MEM, MEM/WB.
>
> My area is the front half. In fetch I have the program counter, the
> instruction memory, and the next-PC logic. In decode, the register
> file, the immediate generator, and the main control unit.
>
> Two design decisions worth calling out.
>
> **First, we used a Harvard memory** — separate instruction and data
> memories. That removes the structural hazard between fetch and memory
> completely. With one unified memory every load and store would collide
> with an instruction fetch and we'd stall constantly.
>
> **Second, and this is the one that matters most** — control signals are
> generated **once**, here in decode, and then travel down the pipeline
> *inside* the pipeline registers alongside the data. They are never
> recomputed in a later stage. Recomputing control from whatever
> instruction a later stage happens to be holding is the classic
> pipelining bug: the control ends up applied to the wrong instruction.
> So ID/EX carries not just the operands but the whole control bundle."

> [DO: scroll to the ID/EX instantiation in `riscv_pipeline.v`, or the
> pipeline-register table in §3.1 of the report]
>
> "You can see that in the ID/EX register — reg_write, alu_src, alu_ctrl,
> mem_read, mem_write, mem_to_reg, branch — all carried as data."

### Register file detail (~45 s)

> [ON SCREEN: `rtl/common/regfile.v`]
>
> "One detail in the register file that's load-bearing. It has a
> write-to-read bypass: if decode reads a register that write-back is
> writing in the same cycle, it returns the new value directly. That
> removes an entire class of hazard before the hazard logic even sees it.
>
> And it's parameterised, because it has to be **off** in the
> single-cycle core. There, the read and the write belong to the *same*
> instruction, so the bypass closes a combinational loop — the ALU output
> feeds its own input. We actually hit that during bring-up; it hung the
> simulator. It's written up in the report."

### Live: instruction overlap (~50 s)

> [DO: run this]

```bash
./sim/run.sh fwd independent +trace
```

> "This is the pipeline actually overlapping instructions. Look at the
> columns — the IF program counter, then ID, EX, MEM, WB. By cycle five
> all five are occupied: five different instructions in flight
> simultaneously. Sixteen instructions finish in
> twenty cycles instead of eighty.
>
> That four-cycle difference is the pipeline fill, and it's why our CPI
> on short programs is 1.25 rather than 1.0.
>
> This program has no dependencies and no branches at all, which makes it
> our control case — nothing to forward, nothing to stall for. Kunal will
> show you what happens when instructions *do* depend on each other."

**To trim:** cut the register-file section (45 s).
**To expand:** walk `control_unit.v`'s opcode decode, and the immediate
generator's three formats (I, S, B).

---

# PART 2 — Kunal: Hazards (~4.5 min)

### The problem (~40 s)

> [ON SCREEN: `docs/REPORT.md` §4, the hazard table]
>
> "Thanks. So overlapping instructions is the point of pipelining, but it
> creates problems, and handling them is my area.
>
> We analysed which hazards can actually occur. **Write-after-read and
> write-after-write can't** — we issue in order, every instruction writes
> exactly one register, and all writes happen in write-back through a
> single port, so they commit in program order. **Structural hazards
> can't** — separate memories, and the register file has exactly the two
> read ports and one write port an instruction needs.
>
> That leaves two real ones: **read-after-write** data hazards, and
> **control** hazards from branches. I'll take them in turn."

### Forwarding (~55 s)

> [ON SCREEN: `rtl/pipelined/forwarding_unit.v`]
>
> "A read-after-write hazard is when an instruction needs a result that
> hasn't been written back yet. The key insight is that an ALU result
> physically **exists** at the end of execute — it just hasn't reached the
> register file. So we forward it directly.
>
> Two paths cover every case: EX/MEM back into execute for a distance-one
> dependency, and MEM/WB into execute for distance two. Beyond that, the
> register file's own bypass handles it.
>
> **Priority matters here.** If both EX/MEM and MEM/WB are writing the
> same register, the correct one is EX/MEM — that's the *younger*
> instruction, its write happens later in program order. Check MEM/WB
> first and you forward a stale value. We have a directed test for
> exactly that.
>
> We also exclude rd equals x0, because writes to x0 are discarded, so
> forwarding one would deliver a value that's never architecturally
> visible."

### Load-use: the one that can't be fixed (~70 s)

> [ON SCREEN: `rtl/pipelined/hazard_unit.v`, the ASCII timing diagram in
> the header]
>
> "Now the interesting one. Exactly one data hazard **cannot** be
> forwarded away, and it's a load followed by an instruction that uses
> the loaded value.
>
> Look at the timing. The load is in MEM during cycle four — that's when
> memory returns the data. But the consumer needs it at the **start** of
> cycle four, for its own execute. Forwarding can move a value across the
> pipeline; it can't move it backwards in time.
>
> So one bubble is unavoidable. We stall fetch and IF/ID, inject a NOP
> into ID/EX, and after that bubble the MEM/WB path delivers the value."

> [DO: run this]

```bash
./sim/run.sh fwd load_use +trace
```

> "There it is, live. **Cycle four** — the hazard unit detects it, you can
> see STALL in the event column. The program counter holds at 12 across
> cycles four and five, it doesn't advance. And **cycle five** shows the
> bubble as a double-dash in the execute column. Then the add proceeds
> with the forwarded value.
>
> Four load-use pairs in this program, four stalls, and the cycle count is
> exactly thirteen instructions plus four fill plus four stalls — 21."

### Flush safety — the most important line (~55 s)

> [ON SCREEN: `rtl/pipelined/id_ex.v`, the bubble logic]
>
> "For control hazards, branches resolve in execute, two cycles after
> fetch, so a wrong guess means discarding two instructions.
>
> And this is the single most important line in my whole area. When we
> insert a bubble, we clear **every control bit** — not just the valid
> bit. reg_write, mem_write, mem_read, branch, all of them go to zero.
>
> Here's why that matters. If a bubble only cleared `valid`, a flushed
> store would still have mem_write asserted, and it would **write
> memory**. Nothing downstream checks valid before the memory write
> unless you make it. You'd get memory corruption that only surfaces much
> later when something loads the value back — the hardest possible bug to
> find.
>
> So we have a test specifically for it: group ten of our hazard suite
> puts a store in a flushed slot and asserts the target memory word is
> still zero. If anyone 'simplifies' this logic, that assertion fires."

### The branch predictor (~70 s)

> [ON SCREEN: `results/trace_array_sum_fwd.txt`]
>
> "Our measurements showed the branch penalty was two thirds of all our
> lost cycles, so we added a branch predictor — 64 entries of 2-bit
> saturating counter.
>
> Here's the loop without it. Static not-taken prediction. Every single
> iteration, fetch loads PC 32 — the instruction *after* the loop — and
> every single iteration we throw it away. You can see MISPREDICT, then
> two dead slots. Seven cycles per iteration."

> [DO: open `results/trace_array_sum_pred.txt` side by side, or run it]

```bash
./sim/run.sh pred array_sum +trace
```

> "Same loop, with the predictor. **Scroll to around cycle 16** — that's
> steady state. No mispredict events, no dead slots. And look at the
> program counter between cycles 15 and 16 — it goes 24, then straight to
> 12, the loop target. The wrong-path instruction is never even fetched.
> Five cycles per iteration instead of seven.
>
> The very first iteration *does* still mispredict — around cycle 10 —
> because the counter starts weakly-not-taken and has to learn. Across the
> whole trace it's 15 mispredicts without the predictor and **2** with it:
> loop entry and loop exit, and nothing else.
>
> My side of the predictor is the correction logic in execute. Static
> prediction can only ever be wrong in one direction, so it only needs the
> branch target. A predictor that can say 'taken' can also be **wrong**
> about that, and then we have to recover to the fall-through path. So the
> redirect target became a multiplexer, not just the branch adder.
>
> One last point on my area: with control hazards handled, the load-use
> bubble is now the **only** remaining overhead. So if we continued this,
> the next step isn't a better predictor — it's compiler scheduling to
> fill that slot."

**To trim:** cut the forwarding-priority detail (20 s) and shorten the
predictor section to just the two traces.
**To expand:** show `tb_hazards.v` group 10 and run it.

---

# PART 3 — P2: Verification and results (~4 min)

### Three independent checks (~60 s)

> [ON SCREEN: `tb/` directory]
>
> "I own verification and measurement. We prove correctness three
> independent ways, because any one of them alone has a blind spot.
>
> **Unit tests** on the ALU and register file.
>
> **A directed hazard test** — 34 assertions, one group per hazard class,
> each failing loudly and naming the mechanism it tests. Forwarding
> priority, x0 handling, load-use, store-data forwarding, branch flush,
> and the flushed-store case Kunal just described.
>
> **And a golden-model comparison**, which is the one that actually
> matters. Every benchmark runs on all four cores, and each dumps an
> architectural signature — registers x1 to x31 and the first 32 words of
> data memory. The pipelined signatures must match the single-cycle
> reference byte for byte.
>
> That's the check that proves the pipeline **correct**. Counting cycles
> only proves it's fast."

### Live: the regression (~45 s)

> [DO: run this]

```bash
./sim/run_all.sh
```

> "That's the entire regression — assemble, build four configurations, unit
> tests, 34 hazard assertions on each config, seven benchmarks times four
> configs, and the golden-model comparison. In about a second.
>
> 34 out of 34 on every configuration. 21 out of 21 signature matches.
> ALL CHECKS PASSED.
>
> There's a fourth check too, and it's a strong one: for every pipelined
> run, cycles equals instructions, plus four for pipeline fill, plus stall
> cycles, plus twice the mispredictions. **That identity holds exactly on
> all 21 runs.** Any unexplained cycle would mean a stall we're taking but
> not reporting."

### Performance (~70 s)

> [ON SCREEN: `results/perf.md`]
>
> "Seven benchmarks, 523 instructions. Here's CPI across the four
> configurations.
>
> Single-cycle is 1.000 by definition. The naive pipeline is **2.302** —
> hazards are expensive. Forwarding brings it to **1.620**. The predictor
> takes it to **1.245**.
>
> Together those two features remove **553 of the 681** hazard cycles the
> naive pipeline paid — 81% of the overhead.
>
> On prediction accuracy: static not-taken gets **11.7%**. The 2-bit table
> gets **93.3%**, removing 98 of 106 mispredictions.
>
> And something we liked — the predictor misses **exactly twice per
> loop**, on every single benchmark. Once on entry, because the counter
> starts weakly-not-taken, and once on exit. That's precisely what the
> theory predicts, and seeing it come out exactly right on all four
> branchy benchmarks was good confirmation the hardware does what we
> think."

### The headline (~55 s)

> [ON SCREEN: `results/synth_summary.md`, the net speedup table]
>
> "Now the result I'd most want you to take away, and it surprised us.
>
> Look at cycle counts alone and pipelining looks like a **failure** —
> CPI went from 1.0 to 1.245. But the two cores can't run at the same
> clock frequency. The single-cycle core's clock period has to cover all
> five stages in series; the pipelined one only the slowest single stage.
> From synthesis that's a 1.64x shorter period.
>
> So multiply them out. Naive pipeline: **0.71x** — genuinely slower than
> single-cycle. Add forwarding: **1.01x**, break-even. Add the predictor:
> **1.32x**.
>
> **Pipelining on its own is not a performance win. Pipelining plus
> hazard mitigation is.** That's the central finding, and we'd have missed
> it entirely if we'd only built the final configuration."

### Area and what's left (~40 s)

> [ON SCREEN: the area table in `results/synth_summary.md`]
>
> "Briefly on cost. Forwarding is the best value in the design: **288
> gates and zero flip-flops** for a 1.42x speedup, because it's pure
> combinational logic. The predictor costs 1071 gates and 136 flip-flops,
> almost all of it the table itself — 64 entries times 2 bits.
>
> Synthesis also told us where the bottleneck is: the execute stage, 70
> gate levels, of which the ALU adder alone is 67. So to go faster you'd
> replace the adder, not re-balance the stages.
>
> What's left is FPGA numbers — real LUT counts and Fmax. That needs
> Vivado, which doesn't run on macOS, so it's one command on a Windows
> machine. The flow is written and validated, and it'll also settle one
> open question: our predictor is free in clock period **only** because
> that ripple-carry adder is so deep. Vivado uses dedicated carry chains,
> so execute will shrink and fetch may become the critical path. We've
> written that section to be confirmed or overturned by the measurement.
>
> Thanks for watching."

**To trim:** cut the area section (40 s).
**To expand:** run `./sim/synth.sh` live (12 s — talk over it) or open a
VCD in GTKWave.

---

## Command cheat sheet

Every command, in order of appearance. All run from the project root.

```bash
./sim/run.sh fwd independent +trace
```

```bash
./sim/run.sh fwd load_use +trace
```

```bash
./sim/run.sh pred array_sum +trace
```

```bash
./sim/run_all.sh
```

Files to have open: `results/perf.md`,
`results/synth_summary.md`, `results/trace_array_sum_fwd.txt`,
`results/trace_array_sum_pred.txt`.

---

## Numbers you must get right on camera

| Claim | Value |
|---|---|
| Configurations | 4 (1 single-cycle + 3 pipelined) |
| Benchmarks / instructions | 7 / 523 |
| CPI | 1.000 / 2.302 / 1.620 / 1.245 |
| IPC | 1.000 / 0.434 / 0.617 / 0.803 |
| Net speedup | 1.00x / 0.71x / 1.01x / 1.32x |
| Hazard cycles removed | 553 of 681 (81%) |
| Forwarding | 1.42x, +288 gates, **0** flip-flops |
| Predictor | 1.30x, +1071 gates, +136 flip-flops |
| Prediction accuracy | 11.7% → 93.3% |
| Mispredictions removed | 98 of 106 (196 cycles) |
| Hazard assertions | 34/34 on each of 4 configs |
| Golden-model matches | 21/21 |
| Deepest stage | EX, 70 gate levels (ALU alone 67) |
| IF depth | 30 without predictor, 56 with |

If you are unsure of a number on camera, say "around" rather than
guessing a precise figure — an evaluator checking a wrong exact number
against the report is worse than a hedge.
