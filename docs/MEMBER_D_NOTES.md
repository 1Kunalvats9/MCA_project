# Member D — Back End: your brief

Your area is everything after the ALU, plus the hazard detection logic.
This is the smallest amount of RTL of the five roles but it owns the two
things most likely to be probed in evaluation: **what stops a flushed
instruction from corrupting state**, and **why the load-use stall is
unavoidable**.

## Files you own

| File | What it is |
|---|---|
| `rtl/common/dmem.v` | data memory |
| `rtl/pipelined/mem_stage.v` | stage 4 wrapper |
| `rtl/pipelined/mem_wb.v` | MEM/WB pipeline register |
| `rtl/pipelined/wb_stage.v` | stage 5, write-back mux |
| `rtl/pipelined/hazard_unit.v` | stall and bubble generation |

Every one of these has a long header comment explaining not just what it
does but why it is built that way. Read those first — they are written to
be the answers to the questions below.

---

## The five things you should be able to explain cold

### 1. Why the data memory read is combinational, not registered

The MEM stage is one cycle and MEM/WB has to capture the loaded word at
the end of that same cycle. A registered read would present the data one
cycle later, during WB, and MEM/WB would latch stale data. A
registered-read memory would force either a second memory stage or a
mandatory one-cycle stall on *every* load.

**The cost, and say this before you are asked:** an asynchronous-read
memory maps to distributed LUT RAM on an FPGA, not to block RAM, because
block RAMs have a registered read port. At 1024 words that costs LUTs but
fits comfortably on an Artix-7. Changing it would mean restructuring the
MEM stage.

### 2. Why the load-use hazard cannot be forwarded away

Draw this:

```
cycle:          1    2    3    4    5    6
lw   x1,0(x2)   IF   ID   EX   MEM  WB
add  x3,x1,x4        IF   ID   EX   MEM  WB
                                ^
                   needs x1 at the START of cycle 4,
                   memory returns it DURING cycle 4
```

The value does not exist yet when the consumer needs it. Forwarding moves
a value *across* the pipeline, it cannot move it *backwards in time*. One
bubble is the minimum, and after that bubble the MEM/WB → EX path delivers
it.

Contrast with an ALU result, which exists at the end of EX — exactly one
cycle before the consumer's EX begins — which is why those forward for
free.

### 3. Why a bubble clears every control bit, not just `valid`

This is the single most important line in the hazard design.

If a bubble cleared only `valid`, a flushed `sw` would still have
`mem_write` asserted and would write the data memory. Nothing downstream
checks `valid` before the memory write unless you make it. The result is
memory corruption that only surfaces much later when something loads the
value back — the hardest class of bug in this design to track down.

So `id_ex.v` clears `reg_write`, `mem_read`, `mem_write`, `mem_to_reg`,
`branch` and `branch_ne` on a bubble, and `mem_stage.v` / `wb_stage.v`
additionally AND their enables with `valid` as a safety belt. The belt is
one gate and it means a single missed clear upstream cannot silently
corrupt state.

**Group 10 of `tb_hazards.v` exists precisely to catch this**: it puts a
`sw` in a flushed slot and asserts the target memory word is still zero.
If someone "simplifies" the bubble logic to clear only `valid`, that
assertion fires. Point at this test — it is the strongest single piece of
evidence of verification quality in your area.

### 4. Why MEM/WB carries both `alu_result` and `mem_data`

It would save 32 flip-flops to mux them at the end of MEM and carry one
`wb_data` field. We carry both and mux in WB because:

- The forwarding unit forwards from MEM/WB. Carrying both means the
  forward path selects exactly the value WB will write, using the same
  `mem_to_reg` bit, with no duplicated mux. If the two were computed
  separately, a load could forward its ALU result — which is the *address*
  — instead of the loaded data. That is a nasty bug because an address is
  a plausible-looking number.
- In a waveform you can see both candidate values side by side, so a
  mis-selected write-back source is obvious rather than subtle.

The 32 flip-flops are reported as the cost of that choice in §3.1 of the
report.

### 5. Why the hazard unit needs `uses_rs1` / `uses_rs2`

For `addi` and `lw`, the `instr[24:20]` field is **part of the
immediate**, not an `rs2` register number. Without these signals from the
control unit, the hazard detector would compare a producer's `rd` against
immediate bits and stall on a dependency that does not exist. Those false
stalls silently inflate CPI — the design still computes the right answer,
so only a careful CPI analysis would reveal it.

Similarly, `rd == x0` is excluded everywhere: writes to `x0` are
discarded, so stalling for one wastes cycles and forwarding one delivers a
value that is never architecturally visible. **Both the hazard unit and
the forwarding unit must apply this exclusion** — getting it right in only
one produces a bug that appears exclusively in code using `x0` as a
scratch destination. Group 4 of `tb_hazards.v` covers it.

---

## How the predictor changed your area

The hazard unit itself is unchanged — it only ever dealt with data
hazards, and the predictor is control-flow. But two things that touch
your code are now different, and you should know them:

**1. The flush signal is driven by a MISPREDICT, not by a taken branch.**
With static not-taken those were the same event, because a not-taken
policy mispredicts exactly the taken branches. With the predictor they
diverge: a correctly predicted taken branch causes no flush at all. The
cycle-accounting identity you quote changed accordingly:

```
cycles == instructions + 4 (fill) + stall_cycles + 2 x MISPREDICTIONS
```

**2. Your bubble-clears-all-control-bits argument matters MORE, not
less.** The predictor can now be wrong in both directions, so flushes
happen after a wrongly-predicted-taken branch as well — meaning
instructions from a path that was never going to execute get further than
before. Group 10 of `tb_hazards.v` (a `sw` in a flushed slot must not
write memory) is still the test that proves it is safe, and it passes on
all four configurations.

**3. The load-use bubble is now the dominant remaining overhead.** This is
the most useful thing to say about your area. With the predictor handling
control hazards, the per-iteration decomposition of `vecsum64` is:

```
4 cycles useful work  +  1 load-use bubble  +  0 branch penalty  =  5
```

So the one remaining source of lost cycles in the whole design is yours.
If asked what to do next, the answer is not a better predictor — it is
compiler scheduling to fill the load-use slot, or a deeper bypass.

---

## The two hazard-unit modes, in one table

| | `FORWARD_EN = 1` | `FORWARD_EN = 0` |
|---|---|---|
| Stall condition | load in EX whose `rd` is read by ID | any producer in EX **or** MEM whose `rd` is read by ID |
| Distance-1 ALU dependency | 0 bubbles | 2 bubbles |
| Distance-2 ALU dependency | 0 bubbles | 1 bubble |
| Load-use | 1 bubble | 2 bubbles |
| Distance 3+ | 0 | 0 (register file write-to-read bypass) |

Why "EX or MEM" and not "EX, MEM or WB": the register file has an internal
write-to-read bypass, so ID can read a value being written by an
instruction in WB during the same cycle. That removes the WB→ID case from
the hazard unit entirely. Know this — it is why the stall-only
configuration costs 2 bubbles and not 3.

---

## Numbers from your area to quote

- Steady-state CPI, `vecsum64`: **1.277** with the predictor (1.746
  without), decomposing per 4-instruction loop iteration as 4 useful +
  **1 load-use bubble** + 0 branch penalty = 5 cycles. With control
  hazards handled, the load-use bubble is the *only* remaining overhead —
  and it is yours.
- Forwarding (which your hazard unit switches between) removes **357 of
  681** hazard cycles across the suite, for **+288 gates and 0
  flip-flops** — the best value in the design.
- `tb_hazards.v`: **34/34 assertions pass on all four configurations.**
- Cycle accounting holds exactly on all 21 pipelined runs:
  `cycles == instructions + 4 + stalls + 2 x mispredictions`.

---

## Likely questions, with short answers

**"What happens if two instructions want to write the same register?"**
Nothing — there is no WAW hazard. In-order issue, one architectural write
per instruction, all writes in WB through a single port, so they commit in
program order.

**"Why is there no stall input on MEM/WB?"**
Stalls are only ever inserted in front of EX. Nothing downstream of EX can
be blocked, because the memory answers in a single cycle. If a multi-cycle
memory were added, MEM/WB is the register that would need a hold input and
the hazard unit would need a back-pressure path. This is written up in the
header of `mem_wb.v`.

**"Can a store and a load to the same address conflict?"**
No. Only one instruction is in MEM at a time, so a `sw` followed by a `lw`
of the same address are at least one cycle apart and the write has already
committed. Group 5 of the directed test covers it.

**"Is the store data forwarded?"**
Yes, but not in your stage — the rs2 forwarding mux is in EX, so the value
reaching `mem_stage` is already architecturally correct. That is
deliberate: it means the MEM stage needs no forwarding logic at all.
Group 6 tests it.

---

## Your demo

```bash
./sim/run_all.sh                         # 34/34 x 4 configs + 21/21, all green
./sim/run.sh fwd load_use +trace         # your load-use bubble, live
./sim/run.sh pred array_sum +trace       # the bubble that is LEFT after
                                         # the predictor removes the rest
```

Then show `results/trace_load_use_fwd.txt` cycles 4–7 and point at the
`--` in the EX column: that is your hazard unit inserting a bubble.
