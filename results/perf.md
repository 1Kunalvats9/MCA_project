## CPI by benchmark and configuration

| Benchmark | Instrs | Single-cycle | Stall only | Forwarding | Fwd + predictor | Forwarding gain | Predictor gain |
|---|---|---|---|---|---|---|---|
| independent | 16 | 1.000 | 1.250 | 1.250 | 1.250 | 1.00x | 1.00x |
| dep_chain | 16 | 1.000 | 3.125 | 1.250 | 1.250 | 2.50x | 1.00x |
| load_use | 13 | 1.000 | 2.077 | 1.615 | 1.615 | 1.29x | 1.00x |
| array_sum | 68 | 1.000 | 2.441 | 1.735 | 1.353 | 1.41x | 1.28x |
| branch_mix | 45 | 1.000 | 1.956 | 1.489 | 1.178 | 1.31x | 1.26x |
| fib | 105 | 1.000 | 1.971 | 1.400 | 1.076 | 1.41x | 1.30x |
| vecsum64 | 260 | 1.000 | 2.485 | 1.746 | 1.277 | 1.42x | 1.37x |

## Cycle counts

| Benchmark | Instrs | Single-cycle | Stall only | Forwarding | Fwd + predictor |
|---|---|---|---|---|---|
| independent | 16 | 16 | 20 | 20 | 20 |
| dep_chain | 16 | 16 | 50 | 20 | 20 |
| load_use | 13 | 13 | 27 | 21 | 21 |
| array_sum | 68 | 68 | 166 | 118 | 92 |
| branch_mix | 45 | 45 | 88 | 67 | 53 |
| fib | 105 | 105 | 207 | 147 | 113 |
| vecsum64 | 260 | 260 | 646 | 454 | 332 |

## Where the cycles go (pipelined configurations)

| Benchmark | Config | Instrs | Cycles | Pipeline fill | Stall cycles | Mispredicts | Flushed slots | Accounted |
|---|---|---|---|---|---|---|---|---|
| independent | Stall only | 16 | 20 | 4 | 0 | 0 | 0 | yes |
| independent | Forwarding | 16 | 20 | 4 | 0 | 0 | 0 | yes |
| independent | Fwd + predictor | 16 | 20 | 4 | 0 | 0 | 0 | yes |
| dep_chain | Stall only | 16 | 50 | 4 | 30 | 0 | 0 | yes |
| dep_chain | Forwarding | 16 | 20 | 4 | 0 | 0 | 0 | yes |
| dep_chain | Fwd + predictor | 16 | 20 | 4 | 0 | 0 | 0 | yes |
| load_use | Stall only | 13 | 27 | 4 | 10 | 0 | 0 | yes |
| load_use | Forwarding | 13 | 21 | 4 | 4 | 0 | 0 | yes |
| load_use | Fwd + predictor | 13 | 21 | 4 | 4 | 0 | 0 | yes |
| array_sum | Stall only | 68 | 166 | 4 | 64 | 15 | 30 | yes |
| array_sum | Forwarding | 68 | 118 | 4 | 16 | 15 | 30 | yes |
| array_sum | Fwd + predictor | 68 | 92 | 4 | 16 | 2 | 4 | yes |
| branch_mix | Stall only | 45 | 88 | 4 | 21 | 9 | 18 | yes |
| branch_mix | Forwarding | 45 | 67 | 4 | 0 | 9 | 18 | yes |
| branch_mix | Fwd + predictor | 45 | 53 | 4 | 0 | 2 | 4 | yes |
| fib | Stall only | 105 | 207 | 4 | 60 | 19 | 38 | yes |
| fib | Forwarding | 105 | 147 | 4 | 0 | 19 | 38 | yes |
| fib | Fwd + predictor | 105 | 113 | 4 | 0 | 2 | 4 | yes |
| vecsum64 | Stall only | 260 | 646 | 4 | 256 | 63 | 126 | yes |
| vecsum64 | Forwarding | 260 | 454 | 4 | 64 | 63 | 126 | yes |
| vecsum64 | Fwd + predictor | 260 | 332 | 4 | 64 | 2 | 4 | yes |

## IPC by benchmark and configuration

| Benchmark | Single-cycle | Stall only | Forwarding | Fwd + predictor |
|---|---|---|---|---|
| independent | 1.000 | 0.800 | 0.800 | 0.800 |
| dep_chain | 1.000 | 0.320 | 0.800 | 0.800 |
| load_use | 1.000 | 0.481 | 0.619 | 0.619 |
| array_sum | 1.000 | 0.410 | 0.576 | 0.739 |
| branch_mix | 1.000 | 0.511 | 0.672 | 0.849 |
| fib | 1.000 | 0.507 | 0.714 | 0.929 |
| vecsum64 | 1.000 | 0.402 | 0.573 | 0.783 |

## Aggregate over all benchmarks

| Configuration | Total instrs | Total cycles | Overall CPI | Overall IPC | Cycles saved vs previous |
|---|---|---|---|---|---|
| Single-cycle | 523 | 523 | 1.000 | 1.000 | - |
| Pipelined (stall only) | 523 | 1204 | 2.302 | 0.434 | -681 (0.43x) |
| Pipelined (forwarding) | 523 | 847 | 1.620 | 0.617 | 357 (1.42x) |
| Pipelined (fwd + 2-bit predictor) | 523 | 651 | 1.245 | 0.803 | 196 (1.30x) |

## Branch prediction accuracy

Static not-taken (the `fwd` configuration) mispredicts exactly the taken branches. The 2-bit branch history table (`pred`) learns each branch's behaviour.

| Benchmark | Branches | Taken | Static NT mispredicts | Static NT accuracy | 2-bit BHT mispredicts | 2-bit BHT accuracy |
|---|---|---|---|---|---|---|
| array_sum | 16 | 15 | 15 | 6.2% | 2 | 87.5% |
| branch_mix | 20 | 9 | 9 | 55.0% | 2 | 90.0% |
| fib | 20 | 19 | 19 | 5.0% | 2 | 90.0% |
| vecsum64 | 64 | 63 | 63 | 1.6% | 2 | 96.9% |
| **total** | **120** | **106** | **106** | **11.7%** | **8** | **93.3%** |

The predictor removes **98 of 106** mispredictions, worth **196 cycles** of flushed work.

### Note on honest speedup

Cycle count alone overstates the benefit of pipelining, because the single-cycle core needs a much longer clock period. The fair comparison is

    speedup = (T_single x cycles_single) / (T_pipe x cycles_pipe)

with T taken from the synthesis timing report (see results/synth_*.txt).
