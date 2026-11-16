# fib.s - iterative Fibonacci, 20 iterations.
#
# A dependency-dense loop with no memory traffic in the body: every add
# inside the loop consumes a value produced one or two instructions
# earlier.  This is the benchmark where forwarding matters most in a
# realistic setting (dep_chain.s is the synthetic extreme), and at 105
# instructions it is long enough that the 4-cycle pipeline fill is no
# longer a significant fraction of the total, so its CPI is close to the
# steady-state value.
#
# Computes fib(21) = 10946.
# Expected: x2 = 10946, x4 = 20, dmem[0] = 10946

addi x1, x0, 0         # a = 0
addi x2, x0, 1         # b = 1
addi x3, x0, 20        # iteration count
addi x4, x0, 0         # i = 0
loop:
add  x5, x1, x2        # t = a + b
add  x1, x2, x0        # a = b       (needs x2, distance 2)
add  x2, x5, x0        # b = t       (needs x5, distance 2)
addi x4, x4, 1         # i++
bne  x4, x3, loop      # taken 19 times
sw   x2, 0(x0)
