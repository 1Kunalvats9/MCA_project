# branch_mix.s - branch dominated code, both outcomes exercised.
#
# A countdown loop with an extra not-taken branch in the body, so the
# program contains a mix of taken and not-taken branches.  Because this
# core statically predicts not-taken, the not-taken branches are free and
# the taken ones each cost two flushed slots: the measured cycle count
# should be close to instructions + fill + 2 * (taken branches).
#
# Expected: x1 = 0, x2 = 10 (loop body ran 10 times), x3 = 0
#           dmem[0] = 10

addi x1, x0, 10        # counter
addi x2, x0, 0         # body execution count
addi x3, x0, 0         # scratch
addi x4, x0, 7         # constant for the not-taken test
loop:
addi x2, x2, 1         # body
beq  x4, x0, never     # NOT taken (7 != 0), costs nothing
addi x1, x1, -1        # counter--
bne  x1, x0, loop      # taken 9 times, falls through on the 10th
never:
sw   x2, 0(x0)
