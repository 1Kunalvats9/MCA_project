# hazard_suite.s - directed test, one case per hazard class.
#
# Run by tb/tb_hazards.v, which checks every register against a hardcoded
# expected value.  Unlike the benchmarks, this program is not about
# performance: each group below fails loudly if a specific piece of the
# hazard logic is wrong, and the comment says which.

# ---- group 1: basic arithmetic, distance-1 and distance-2 RAW ----------
# A broken EX/MEM -> EX forward shows up as x3 or x5 being wrong.
addi x1,  x0, 10          # x1  = 10
addi x2,  x0, 3           # x2  = 3
add  x3,  x1, x2          # x3  = 13   (x2 distance 1, x1 distance 2)
sub  x4,  x1, x2          # x4  = 7
add  x5,  x3, x4          # x5  = 20   (x4 distance 1, x3 distance 2)

# ---- group 2: distance-2 only (MEM/WB -> EX path) ----------------------
# Fails if the MEM/WB forward path or its priority is wrong.
addi x6,  x0, 100         # x6  = 100
addi x7,  x0, 1           # filler, independent
add  x8,  x6, x6          # x8  = 200  (x6 at distance 2)

# ---- group 3: forwarding priority, younger producer must win ----------
# Two writes to the same register back to back; the consumer must see the
# second one.  Fails if the forwarding unit checks MEM/WB before EX/MEM.
addi x9,  x0, 1           # x9 = 1   (older write, will be in MEM/WB)
addi x9,  x0, 2           # x9 = 2   (younger write, will be in EX/MEM)
add  x10, x9, x0          # x10 = 2, NOT 1

# ---- group 4: x0 must never be forwarded ------------------------------
# add x0,... computes 13 but the register file discards it.  If the
# forwarding unit forgets the rd != x0 exclusion, x12 becomes 23.
add  x0,  x1, x2          # discarded, x0 stays 0
add  x12, x0, x1          # x12 = 10, NOT 23

# ---- group 5: load-use (the one stall forwarding cannot remove) -------
addi x13, x0, 64          # base = 64 -> dmem word 16
addi x14, x0, 20
sw   x14, 0(x13)          # dmem[16] = 20
lw   x15, 0(x13)          # x15 = 20
add  x16, x15, x15        # x16 = 40   (load-use, needs 1 bubble)

# ---- group 6: store data forwarding -----------------------------------
# The value stored is produced by the instruction immediately before the
# sw.  The rs2 forwarding mux must sit before the store-data path; if it
# sits after, dmem[17] and therefore x18 hold a stale value.
add  x17, x1, x1          # x17 = 20
sw   x17, 4(x13)          # dmem[17] = 20, store data forwarded
lw   x18, 4(x13)          # x18 = 20

# ---- group 7: branch NOT taken ----------------------------------------
addi x19, x0, 5
addi x20, x0, 5
bne  x19, x20, skip1      # NOT taken (5 == 5)
addi x21, x0, 1           # must execute -> x21 = 1
skip1:

# ---- group 8: branch taken, two following slots must be flushed -------
# If the flush clears only the valid bit and not the control bits, or
# flushes only one slot, x22 or x23 end up as 99.
beq  x19, x20, skip2      # taken
addi x22, x0, 99          # MUST NOT execute -> x22 stays 0
addi x23, x0, 99          # MUST NOT execute -> x23 stays 0
skip2:
addi x24, x0, 7           # x24 = 7

# ---- group 9: branch operand forwarded into the comparator ------------
# x26 is produced by the instruction right before the branch, so the
# comparator must read the forwarded value, not the register file.
addi x25, x0, 4
add  x26, x25, x0         # x26 = 4
beq  x26, x25, skip3      # taken, requires forwarding into branch_cmp
addi x27, x0, 99          # MUST NOT execute -> x27 stays 0
skip3:
addi x28, x0, 1           # x28 = 1

# ---- group 10: a flushed store must not reach memory ------------------
# dmem[20] must still be 0 at the end.  This is the test that catches a
# bubble which clears valid but leaves mem_write asserted.
addi x29, x0, 123
beq  x19, x20, skip4      # taken
sw   x29, 16(x13)         # MUST NOT write dmem[20]
addi x30, x0, 99          # MUST NOT execute -> x30 stays 0
skip4:
addi x31, x0, 42          # x31 = 42
