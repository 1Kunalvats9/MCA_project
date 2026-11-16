# load_use.s - repeated load-use pairs.
#
# Each lw is immediately followed by an instruction that consumes the
# loaded value.  This is the one hazard forwarding cannot eliminate, so
# even the forwarding configuration pays one bubble per pair.  Comparing
# this against dep_chain.s separates "hazards forwarding fixes" from
# "hazards forwarding cannot fix", which is the main point of the
# performance discussion in the report.
#
# dmem words 0..3 are preloaded with 10, 20, 30, 40.
# Results are stored back to dmem words 4..7 as 20, 40, 60, 80.
#
# Expected: x1=10 x2=20 x3=20 x4=40 x5=30 x6=60 x7=40 x8=80
#           dmem[4]=20 dmem[5]=40 dmem[6]=60 dmem[7]=80

.data
.word 10
.word 20
.word 30
.word 40

.text
addi x10, x0, 0        # base address = 0
lw   x1,  0(x10)
add  x2,  x1,  x1      # load-use on x1
lw   x3,  4(x10)
add  x4,  x3,  x3      # load-use on x3
lw   x5,  8(x10)
add  x6,  x5,  x5      # load-use on x5
lw   x7,  12(x10)
add  x8,  x7,  x7      # load-use on x7
sw   x2,  16(x10)
sw   x4,  20(x10)
sw   x6,  24(x10)
sw   x8,  28(x10)
