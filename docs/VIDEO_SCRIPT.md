# Prototype video script — 5 minutes, hard limit

Phase I criteria: **must not exceed 5 minutes**, must clearly state the
project idea, must introduce **all 5 group members by name**, must
demonstrate the working prototype.

The longer 12-minute version is kept in `VIDEO_SCRIPT_LONG.md` for a
possible Phase II demo. Do not use it for this submission.

> **Two things to fill in before recording.**
>
> 1. **Who is P2?** Joshit and Kunal are confirmed. If the group is three
>    people, P2 is Dev Kothari — set it and delete `[Member 4]` and
>    `[Member 5]` from the names line below. If the group really is five,
>    put the remaining two names in.
> 2. The names line must match the group exactly: the marking criteria
>    requires every member to be introduced by name.

**Total spoken words below: 644.**

| Your pace | Speech | + demos (~15 s) | Verdict |
|---|---|---|---|
| 160 wpm (brisk) | 4:01 | 4:16 | comfortable |
| 145 wpm (normal) | 4:26 | 4:41 | fine |
| 130 wpm (measured) | 4:57 | 5:12 | **over — must cut** |

**Rehearse with a stopwatch before recording.** If your run-through is
over **4:40**, make the cuts listed at the end of this document. Do not
ad-lib: there is no slack.

---

## Running order

| Time | Who | Section |
|---|---|---|
| 0:00–0:40 | **Joshit** | Idea, all 5 names, what we built |
| 0:40–1:30 | **Joshit** | Architecture and the four configurations |
| 1:30–2:50 | **Kunal** | Hazards + live trace demo |
| 2:50–4:30 | **P2** | Verification + results + the headline |
| 4:30–5:00 | **P2** | Status and close |

Only **two** commands are run live. Everything else is already on screen.

---

## Before recording

```bash
cd /Users/kunalvats/Downloads/Coding/MCA_project && ./sim/run_all.sh
```

Then open and leave open, in this tab order:

1. `results/trace_array_sum_fwd.txt` — scrolled to cycle 9
2. `results/perf.md`
3. `results/synth_summary.md` — scrolled to the net-speedup table

Terminal: 16–18 pt, at least 100 columns wide, `clear` before each
section. Rehearse once with a stopwatch.

---

# 0:00–0:40 — Joshit: Idea and team  *(~95 words)*

> [ON SCREEN: the repo, or a title slide]
>
> "Our project is a **five-stage pipelined RISC-V processor**, written in
> Verilog and verified in simulation.
>
> The group is **Kunal Vats, Dev Kothari, Joshit, [Member 4] and
> [Member 5]**.
>
> We implement a working subset of the RV32I instruction set — add, sub,
> addi, load word, store word, and two branches.
>
> The idea we want to show you is this: we didn't build one processor, we
> built **four**. A single-cycle reference, and three pipelined versions
> that differ only by a parameter. That lets us measure what each
> architectural feature is actually worth, instead of reporting one
> number we can't break down."

---

# 0:40–1:30 — Joshit: Architecture  *(~125 words)*

> [ON SCREEN: the stage diagram, or `riscv_pipeline.v`]
>
> "The datapath is the classic five stages — fetch, decode, execute,
> memory, write-back — with four pipeline registers between them.
>
> Two decisions worth calling out.
>
> We used **separate instruction and data memories**, which removes the
> structural hazard between fetch and memory completely.
>
> And **control signals are decoded once, in decode, then carried down
> the pipeline inside the registers** alongside the data. They're never
> recomputed later. Recomputing control from whatever a later stage
> happens to be holding is the classic pipelining bug — the control ends
> up applied to the wrong instruction.
>
> The four configurations are: single-cycle as our correctness reference,
> then pipelined with no hazard handling, pipelined with forwarding, and
> pipelined with forwarding plus a branch predictor.
>
> Kunal will take the hazards."

---

# 1:30–2:50 — Kunal: Hazards + live demo  *(~185 words + demo)*

> [ON SCREEN: `rtl/pipelined/hazard_unit.v`]
>
> "Overlapping instructions breaks dependencies, and handling that is my
> part.
>
> Write-after-read and write-after-write can't happen here — we issue in
> order through a single write port. So we handle two things:
> read-after-write hazards, and branches.
>
> For data hazards we **forward**: an ALU result already exists at the end
> of execute, so we route it straight back instead of waiting for
> write-back.
>
> Exactly one case resists that — a load, then an instruction using the
> loaded value. Memory returns it *during* the cycle the consumer needs
> it. Forwarding moves a value across the pipeline; it can't move it
> backwards in time. So that one costs a bubble."

> [DO — command 1, takes under a second]

```bash
./sim/run.sh pred array_sum +trace
```

> [POINT at the trace, then at the pre-opened `trace_array_sum_fwd.txt`]
>
> "That's the processor running a loop, cycle by cycle, with the predictor
> on. Around cycle 16 — no mispredict, no wasted slots, and the program
> counter jumps straight back to the loop target.
>
> Compare the window from the version **without** it: every iteration
> mispredicts and throws away two cycles. Seven cycles per iteration
> there, five here.
>
> One last point: when we flush we clear **every** control bit, not just
> the valid bit — otherwise a cancelled store still writes memory."

---

# 2:50–4:30 — P2: Verification and results  *(~190 words + demo)*

> [ON SCREEN: `tb/` folder]
>
> "I own verification. We prove correctness three ways: unit tests, 34
> directed hazard assertions, and a golden-model comparison where all four
> cores run every program and their final register and memory state must
> match **exactly**. That last one is what proves the pipeline correct —
> counting cycles only proves it's fast."

> [DO — command 2, takes about a second]

```bash
./sim/run_all.sh
```

> "That's the whole regression — four configurations, seven benchmarks,
> every test, in about a second. 34 out of 34 on each configuration, 21
> out of 21 golden-model matches."

> [ON SCREEN: `results/perf.md`]
>
> "The results. CPI: the unmitigated pipeline is 2.30, forwarding brings
> it to 1.62, the predictor to 1.25 — together removing 81% of the hazard
> overhead. Prediction accuracy goes from 11.7% to **93.3%**."

> [ON SCREEN: `results/synth_summary.md`, net speedup table]
>
> "And this is the result we'd most want you to see. Cycle counts alone
> make pipelining look like a failure, because CPI went **up** from 1.0.
> But the pipelined core runs at a shorter clock period — from synthesis,
> 1.64 times shorter. Multiply those out.
>
> No hazard handling: **0.71** — genuinely slower than single-cycle.
> Forwarding: **1.01**, break-even. Add the predictor: **1.32**.
>
> So pipelining alone is not a performance win. Pipelining **plus** hazard
> mitigation is. We'd have missed that if we'd only built the final
> version."

---

# 4:30–5:00 — P2: Status and close  *(~45 words)*

> "Where we are: the processor is complete and fully verified in
> simulation, with synthesis results. What's left for Phase II is running
> it through Vivado for real FPGA numbers — that flow is already written.
>
> Everything is in the repository. Thank you."

---

## Timing discipline

Over 5:00 risks the marks for the whole 15-mark video component, so treat
the limit as hard.

**Cuts, in the order to make them.** Each is self-contained — removing it
leaves the surrounding speech coherent.

| # | Cut | Saves |
|---|---|---|
| 1 | Kunal's flush-safety sentence ("One last point… writes memory") | ~28 words / 12 s |
| 2 | Joshit's control-signal paragraph ("And **control signals**… wrong instruction") | ~50 words / 21 s |
| 3 | Kunal's WAR/WAW rule-out ("Write-after-read and… and branches") | ~30 words / 12 s |
| 4 | P2's regression-detail sentence (keep the command, drop the narration) | ~30 words / 12 s |

All four cuts together save about 57 seconds, which brings even a
130 wpm delivery to roughly 4:15.

**Never cut:** the five member names, the project idea, or the two live
demos — all three are explicitly in the marking criteria.

**Record each section separately** and edit them together. Three clean
90-second takes are far easier to get than one clean 5-minute take, and
it lets each person re-record without the others.

## Numbers to get right

| Claim | Value |
|---|---|
| Configurations | 4 |
| CPI | 2.302 → 1.620 → 1.245 |
| Hazard overhead removed | 81% |
| Prediction accuracy | 11.7% → 93.3% |
| Net speedup | 0.71× → 1.01× → 1.32× |
| Clock-period ratio | 1.64× |
| Tests | 34/34 per config, 21/21 golden-model |

If unsure of a figure on camera, say "around" rather than guessing.
