//==========================================================================
// hazard_unit.v - Hazard detection and stall generation
//
// Owner: Member D (Back end)
//
//--------------------------------------------------------------------------
// Purpose
//--------------------------------------------------------------------------
// Decides when the instruction in ID must be held back because a value it
// reads is not yet available.  It drives exactly three signals:
//
//   stall_pc    - freeze the program counter
//   stall_if_id - hold the IF/ID register (re-present the same instruction)
//   bubble_id_ex- inject a NOP into ID/EX
//
// All three are asserted together; they are separate ports only because
// they go to three different modules, which makes the connection obvious
// in the top-level netlist and in a waveform.
//
//--------------------------------------------------------------------------
// FORWARD_EN = 1  (the fast configuration)
//--------------------------------------------------------------------------
// With a full forwarding network, every RAW dependency on an ALU result
// is satisfied without stalling, because the result exists at the end of
// EX and the consumer needs it at the start of its own EX.
//
// Exactly one case cannot be fixed by forwarding: the LOAD-USE hazard.
//
//   cycle:        1    2    3    4    5    6
//   lw  x1,0(x2)  IF   ID   EX   MEM  WB
//   add x3,x1,x4       IF   ID   EX   MEM  WB
//                                 ^
//                       needs x1 at the start of cycle 4,
//                       but the memory only returns it during cycle 4.
//
// Time does not run backwards, so one bubble is unavoidable:
//
//   cycle:        1    2    3    4    5    6    7
//   lw  x1,0(x2)  IF   ID   EX   MEM  WB
//   add x3,x1,x4       IF   ID   **   EX   MEM  WB
//                                 |    ^
//                              bubble  now x1 is forwarded MEM/WB -> EX
//
// Condition: a load is in EX, it writes a non-zero register, and the
// instruction in ID actually reads that register.
//
//--------------------------------------------------------------------------
// FORWARD_EN = 0  (the reference configuration for the CPI comparison)
//--------------------------------------------------------------------------
// With no forwarding paths at all, a value is only readable once it has
// been written into the register file.  The register file has an internal
// write-to-read bypass (see rtl/common/regfile.v), so an instruction in ID
// can read a value being written by an instruction in WB during the same
// cycle.  That means ID must wait for any producer still in EX or MEM, but
// not for one already in WB:
//
//   add x1,x2,x3  IF   ID   EX   MEM  WB
//   add x4,x1,x5       IF   ID   **   **   EX   MEM  WB
//                                 |    |    ^
//                         producer in  in   producer in WB,
//                              EX     MEM   regfile bypass supplies x1
//
// So a distance-1 dependency costs 2 bubbles and a distance-2 dependency
// costs 1.  A load-use pair also costs 2, for the same reason.  This is
// what produces the CPI gap between the two configurations in the report.
//
//--------------------------------------------------------------------------
// Why id_valid gates everything
//--------------------------------------------------------------------------
// A bubble or a flushed slot in ID reads no registers.  Its rs1/rs2 fields
// are zeroed, but x0 is excluded anyway, so the real reason for gating on
// id_valid is robustness: if the ID slot is not a real instruction, there
// is by definition no dependency to protect, and stalling on one would
// deadlock the drain at the end of a program.
//
//--------------------------------------------------------------------------
// Why rd == x0 is always excluded
//--------------------------------------------------------------------------
// Writes to x0 are discarded by the register file, so a producer whose rd
// is x0 never changes any value.  Stalling for it would be pure lost
// cycles, and (in the forwarding unit) forwarding from it would deliver a
// result that is never architecturally visible.  Both units must apply
// this exclusion; getting it wrong in only one of them produces a bug
// that appears exclusively in code using x0 as a scratch destination.
//==========================================================================
`include "defines.vh"

module hazard_unit #(
    parameter FORWARD_EN = 1
) (
    // instruction currently in ID
    input  wire                  id_valid,
    input  wire [4:0]            id_rs1_addr,
    input  wire [4:0]            id_rs2_addr,
    input  wire                  id_uses_rs1,
    input  wire                  id_uses_rs2,

    // instruction currently in EX
    input  wire                  ex_valid,
    input  wire [4:0]            ex_rd_addr,
    input  wire                  ex_reg_write,
    input  wire                  ex_mem_read,

    // instruction currently in MEM
    input  wire                  mem_valid,
    input  wire [4:0]            mem_rd_addr,
    input  wire                  mem_reg_write,

    output wire                  stall_pc,
    output wire                  stall_if_id,
    output wire                  bubble_id_ex
);

    //----------------------------------------------------------------------
    // Does the instruction in ID read a register that EX / MEM will write?
    //----------------------------------------------------------------------
    wire ex_writes_real = ex_valid & ex_reg_write & (ex_rd_addr != 5'd0);
    wire mem_writes_real = mem_valid & mem_reg_write & (mem_rd_addr != 5'd0);

    wire ex_hit = ex_writes_real &
                  ((id_uses_rs1 & (id_rs1_addr == ex_rd_addr)) |
                   (id_uses_rs2 & (id_rs2_addr == ex_rd_addr)));

    wire mem_hit = mem_writes_real &
                   ((id_uses_rs1 & (id_rs1_addr == mem_rd_addr)) |
                    (id_uses_rs2 & (id_rs2_addr == mem_rd_addr)));

    //----------------------------------------------------------------------
    // Load-use: the one hazard forwarding cannot remove.
    //----------------------------------------------------------------------
    wire load_use = ex_writes_real & ex_mem_read &
                    ((id_uses_rs1 & (id_rs1_addr == ex_rd_addr)) |
                     (id_uses_rs2 & (id_rs2_addr == ex_rd_addr)));

    //----------------------------------------------------------------------
    // Stall decision
    //----------------------------------------------------------------------
    wire stall = id_valid & (FORWARD_EN ? load_use
                                        : (ex_hit | mem_hit));

    assign stall_pc     = stall;
    assign stall_if_id  = stall;
    assign bubble_id_ex = stall;

endmodule
