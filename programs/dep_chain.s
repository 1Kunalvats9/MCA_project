# dep_chain.s - worst case RAW dependency chain.
#
# Every instruction uses the result of the one immediately before it, so
# every pair is a distance-1 RAW hazard on an ALU result.
#
#   with forwarding : all satisfied by the EX/MEM -> EX path, 0 stalls
#   without         : 2 bubbles per dependent pair
#
# This is the benchmark that shows the value of the forwarding network
# most clearly, and the two CPI numbers should differ by roughly 2x.
#
# Expected: x1 = 1, then each register is double the previous one.
#   x2=2 x3=4 x4=8 x5=16 x6=32 x7=64 x8=128 x9=256 x10=512 x11=1024
#   x12=2048 x13=4096 x14=8192 x15=16384 x16=32768

addi x1,  x0, 1
add  x2,  x1,  x1
add  x3,  x2,  x2
add  x4,  x3,  x3
add  x5,  x4,  x4
add  x6,  x5,  x5
add  x7,  x6,  x6
add  x8,  x7,  x7
add  x9,  x8,  x8
add  x10, x9,  x9
add  x11, x10, x10
add  x12, x11, x11
add  x13, x12, x12
add  x14, x13, x13
add  x15, x14, x14
add  x16, x15, x15
