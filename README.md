
# 5-Stage Pipelined RISC-V Processor (RV32I subset)

Modern Computer Architecture — Project 3

A five-stage pipelined RISC-V processor in Verilog, built in **four configurations** so the effect of pipelining, of operand forwarding and of dynamic branch prediction can each be measured rather than asserted:

| Configuration | Parameters | Purpose |
|---|---|---|
| Single-cycle | `rtl/single_cycle/` | correctness reference (golden model), CPI = 1.000 by construction |
| Pipelined, stall-only | `FORWARD_EN=0, PREDICTOR=0` | what hazards cost with no mitigation |
| Pipelined, forwarding | `FORWARD_EN=1, PREDICTOR=0` | adds the bypass network |
| Pipelined, fwd + predictor | `FORWARD_EN=1, PREDICTOR=1` | adds a 64-entry 2-bit branch history table |

The three pipelined configurations are built from **identical RTL** and differ only by parameters, and each step adds exactly one feature, so every comparison isolates that feature:

```
stall  --[+ forwarding]-->  fwd  --[+ 2-bit predictor]-->  pred
```

**Instruction set:** `add` `sub` `addi` `lw` `sw` `beq` `bne` (plus `nop`).

---

## Pipeline Architecture

The processor uses a classic five-stage pipeline. Each instruction passes through five stages, with pipeline registers carrying the required data and control signals between stages.

```mermaid
flowchart LR
    IF["IF: Instruction Fetch"] --> IFID["IF/ID Register"]
    IFID --> ID["ID: Instruction Decode"]
    ID --> IDEX["ID/EX Register"]
    IDEX --> EX["EX: Execute"]
    EX --> EXMEM["EX/MEM Register"]
    EXMEM --> MEM["MEM: Memory Access"]
    MEM --> MEMWB["MEM/WB Register"]
    MEMWB --> WB["WB: Write Back"]
```

| Stage | Description |
|---|---|
| **IF – Instruction Fetch** | Fetches the instruction using the program counter and selects the next PC. |
| **ID – Instruction Decode** | Decodes the instruction, reads source registers and generates control signals. |
| **EX – Execute** | Performs ALU operations, operand forwarding and branch resolution. |
| **MEM – Memory Access** | Performs memory reads for LW and memory writes for SW. |
| **WB – Write Back** | Writes the final result into the destination register. |

Pipeline registers preserve instruction information between consecutive stages, allowing multiple instructions to execute simultaneously.

## Data Hazards and Pipeline Control

A data hazard occurs when an instruction requires a register value that an earlier instruction has not yet produced. This processor implements different mechanisms to handle data and control hazards.

### Hazard Handling Techniques

| Technique | How it works |
|---|---|
| **Pipeline Stalling** | Pauses instruction fetching and inserts a bubble when a required value is unavailable. |
| **Operand Forwarding** | Sends results directly from later pipeline stages to the EX stage without waiting for register write-back. |
| **Load-Use Detection** | Detects dependencies involving load instructions and inserts one bubble when forwarding is enabled. |
| **Branch Prediction** | Uses a 64-entry Branch History Table with 2-bit saturating counters to predict branch outcomes. |
| **Pipeline Flushing** | Removes incorrectly fetched instructions when branch prediction is incorrect. |

### Configuration Comparison

- **Single-cycle:** Used as the reference architecture.
- **Stall-only:** Handles dependencies using pipeline stalls without operand forwarding.
- **Forwarding:** Uses bypass paths to reduce unnecessary stalls.
- **Forwarding + Branch Prediction:** Combines forwarding with dynamic branch prediction to reduce control-hazard penalties.

These configurations help demonstrate how different hazard-handling techniques affect CPI, IPC and overall processor performance.

---

## Quick start

Install the toolchain (one time):

```bash
brew install icarus-verilog yosys && brew install --cask gtkwave
```

Run the entire regression, benchmark sweep and report-table generation:

```bash
./sim/run_all.sh
```

Run synthesis (area and logic depth):

```bash
./sim/synth.sh
```

Run the FPGA characterisation — needs Vivado, so Windows or Linux (see [fpga/README.md](fpga/README.md)):

```bash
vivado -mode batch -source fpga/run_vivado.tcl
```

```bash
python3 tools/fpga_table.py
```

Run one program on one configuration, with a pipeline trace (`single` | `stall` | `fwd` | `pred`):

```bash
./sim/run.sh pred array_sum +trace
```

View a waveform:

```bash
gtkwave results/array_sum.fwd.vcd
```

---

## What `run_all.sh` checks

1. Assembles every program in `programs/`
2. Builds all three configurations plus the unit tests
3. **Unit tests** — ALU and register file
4. **Directed hazard test** — 34 assertions covering every hazard class, run on all four configurations
5. **Benchmarks** — 7 programs x 4 configurations
6. **Golden-model check** — the architectural signature (x1–x31 and dmem[0–31]) of each pipelined run must match the single-cycle run byte for byte. This is what actually proves the pipeline correct; counting cycles only proves it is fast.
7. Generates `results/perf.csv` and `results/perf.md`
8. Generates pipeline traces and VCD waveforms for the report

Exit status is non-zero if anything fails, so it works as a pre-submission gate.

---

## Repository map

```
rtl/common/          shared modules
  defines.vh           opcodes, ALU codes, memory sizing
  alu.v                ADD / SUB
  branch_cmp.v         branch condition comparator
  regfile.v            32x32 registers, x0 hardwired, optional WB bypass
  imm_gen.v            I / S / B format immediate extraction
  control_unit.v       opcode -> control bundle
  imem.v               instruction memory (read only)
  dmem.v               data memory

rtl/single_cycle/
  riscv_single_cycle.v the reference core

rtl/pipelined/
  pc_if.v              stage 1: PC + fetch + next-PC select
  if_id.v              IF/ID pipeline register
  decode_stage.v       stage 2: regfile + immgen + control
  id_ex.v              ID/EX pipeline register
  ex_stage.v           stage 3: forwarding muxes + ALU + branch resolve
  branch_predictor.v   64-entry table of 2-bit saturating counters
  ex_mem.v             EX/MEM pipeline register
  mem_stage.v          stage 4: data memory access
  mem_wb.v             MEM/WB pipeline register
  wb_stage.v           stage 5: write-back mux
  forwarding_unit.v    bypass network control
  hazard_unit.v        stall / bubble generation
  riscv_pipeline.v     top level

rtl/synth/             memory blackboxes for synthesis only

tb/
  tb_alu.v             ALU unit test
  tb_regfile.v         register file unit test
  tb_core.v            benchmark harness, performance counters, trace
  tb_hazards.v         directed self-checking hazard test (34 checks)

programs/              benchmarks in assembly, plus generated .hex and .lst

tools/
  asm.py               assembler for the 7-instruction subset
  perf_table.py        perf.csv -> report tables
  synth_table.py       Yosys logs -> report tables
  fpga_table.py        Vivado results -> report tables

sim/
  run.sh               one config, one program
  run_all.sh           full regression + sweep
  synth.sh             Yosys area and depth

fpga/
  run_vivado.tcl       one-command FPGA characterisation, all 4 configs
  wrappers/            one wrapper per configuration, identical ports
  README.md            how to run it, options, troubleshooting

docs/                  report and per-member notes
results/               all generated output (CSV, markdown, traces, VCDs)
```

---

## Team roles

| Member | Area | Files owned |
|---|---|---|
| A | Front end | `pc_if.v`, `if_id.v`, `imem.v`, `branch_predictor.v` |
| B | Decode | `decode_stage.v`, `id_ex.v`, `regfile.v`, `imm_gen.v`, `control_unit.v` |
| C | Execute | `ex_stage.v`, `ex_mem.v`, `alu.v`, `branch_cmp.v`, `forwarding_unit.v` |
| **D** | **Back end** | **`mem_stage.v`, `mem_wb.v`, `wb_stage.v`, `dmem.v`, `hazard_unit.v`** |
| E | Verification & infra | `tb_*.v`, `asm.py`, `perf_table.py`, `synth_table.py`, `sim/*.sh` |

Every RTL file carries an `Owner:` line in its header comment. Per-member notes for the viva are in `docs/`.

---

## Headline results

Measured over 7 benchmarks, 523 instructions total:

| Configuration | Cycles | CPI | IPC | Cycles saved | Net speedup vs single-cycle |
|---|---|---|---|---|---|
| Single-cycle | 523 | 1.000 | 1.000 | — | 1.00x |
| Pipelined, stall-only | 1204 | 2.302 | 0.434 | — | 0.71x |
| Pipelined, forwarding | 847 | 1.620 | 0.617 | 357 (1.42x) | 1.01x |
| Pipelined, fwd + predictor | 651 | 1.245 | 0.803 | 196 (1.30x) | **1.32x** |

The last column is the central result, and it is worth reading down: **the naive pipeline is slower than the single-cycle core**, forwarding brings it to break-even, and the predictor makes it a genuine win. Pipelining on its own is not a performance win — pipelining plus hazard mitigation is. (Net speedup multiplies the cycle ratio by the 1.64x clock-period ratio from synthesis; see §7.5 of the report.)

Together the two features remove **553 of the 681** hazard cycles the naive pipeline paid — 81% of the overhead — for +1359 gates and +136 flip-flops.

**Branch prediction accuracy rises from 11.7% to 93.3%**, removing 98 of 106 mispredictions. The predictor misses exactly twice per loop on every benchmark: once on entry (counter starts weakly not-taken) and once on exit.

Steady-state CPI on the longest benchmark (`vecsum64`, 260 instructions) is **1.277**, which is the figure to quote for sustained performance. `fib` reaches **1.076** — within 7% of the ideal for a scalar pipeline.

### Still to measure

FPGA utilisation and Fmax. Vivado does not run on macOS, so this needs a team member on Windows or Linux; the flow is written and reduced to two commands (above), takes about an hour unattended, and needs no board. It fills §7.8 of the report, replaces the one estimated figure in the headline speedup, and settles whether the predictor stays free in clock period once Vivado maps the adders onto carry chains. See [docs/VIVADO.md](docs/VIVADO.md).

Full tables: `results/perf.md` and `results/synth_summary.md`.

Discussion, including why the net speedup over the single-cycle core is **not** the cycle-count ratio: `docs/REPORT.md`.
