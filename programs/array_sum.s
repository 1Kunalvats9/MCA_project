# array_sum.s - realistic instruction mix: a counted loop over an array.
#
# Sums 16 words from data memory.  Each iteration is:
#     lw   / add  (load-use hazard)
#     addi       (pointer bump)
#     bne        (taken 15 times, not taken once)
#
# So every iteration pays one load-use bubble plus, when the branch is
# taken, two flushed slots.  This is the benchmark whose CPI is closest to
# what real code would see, and the one to quote as the headline number.
#
# dmem words 0..15 = 1..16, sum = 136, stored to dmem word 16.
#
# Expected: x2 = 136, dmem[16] = 136

.data
.word 1
.word 2
.word 3
.word 4
.word 5
.word 6
.word 7
.word 8
.word 9
.word 10
.word 11
.word 12
.word 13
.word 14
.word 15
.word 16

.text
addi x1, x0, 0         # byte offset / pointer
addi x2, x0, 0         # running sum
addi x3, x0, 64        # end offset = 16 words * 4
loop:
lw   x4, 0(x1)         # load a[i]
add  x2, x2, x4        # sum += a[i]   (load-use hazard)
addi x1, x1, 4         # i++
bne  x1, x3, loop      # taken 15 times
sw   x2, 64(x0)        # store the result at dmem[16]
