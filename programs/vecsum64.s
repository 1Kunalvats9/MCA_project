# vecsum64.s - sum a 64-element vector.
#
# The same loop shape as array_sum.s but four times as many iterations,
# giving 260 instructions.  Its purpose is to show the ASYMPTOTIC CPI:
# with 260 instructions the 4-cycle fill is 1.5% of the total rather than
# 25%, so the CPI reported here is essentially the steady-state figure for
# a load-use plus taken-branch loop.  Quote this one, not the short
# benchmarks, when stating the pipeline's sustained performance.
#
# dmem words 0..63 = 1..64, sum = 2080, stored to dmem word 64.
# Expected: x2 = 2080, dmem[64] = 2080

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
.word 17
.word 18
.word 19
.word 20
.word 21
.word 22
.word 23
.word 24
.word 25
.word 26
.word 27
.word 28
.word 29
.word 30
.word 31
.word 32
.word 33
.word 34
.word 35
.word 36
.word 37
.word 38
.word 39
.word 40
.word 41
.word 42
.word 43
.word 44
.word 45
.word 46
.word 47
.word 48
.word 49
.word 50
.word 51
.word 52
.word 53
.word 54
.word 55
.word 56
.word 57
.word 58
.word 59
.word 60
.word 61
.word 62
.word 63
.word 64

.text
addi x1, x0, 0         # byte offset
addi x2, x0, 0         # running sum
addi x3, x0, 256       # end offset = 64 words * 4
loop:
lw   x4, 0(x1)         # load a[i]
add  x2, x2, x4        # sum += a[i]   (load-use)
addi x1, x1, 4         # i++
bne  x1, x3, loop      # taken 63 times
sw   x2, 256(x0)       # dmem[64] = sum
