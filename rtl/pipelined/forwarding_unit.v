//==========================================================================
// forwarding_unit.v - Operand forwarding (bypass) network control
//
// Owner: Member C (Execute stage)
//
// Watches the two source registers of the instruction in EX and decides,
// for each of them, where the up-to-date value should come from:
//
//   FWD_REG - the value read from the register file is already correct
//   FWD_MEM - forward the ALU result sitting in EX/MEM  (distance 1)
//   FWD_WB  - forward the write-back value in MEM/WB    (distance 2)
//
// Priority matters.  If BOTH EX/MEM and MEM/WB are writing the same
// register, the correct value is the one from EX/MEM, because that is the
// younger instruction and its write happens later in program order.
// Checking MEM/WB first would forward a stale value.  Example:
//
//   add x1, x2, x3     <- in MEM/WB, wrote x1 (older)
//   add x1, x4, x5     <- in EX/MEM, writes x1 (younger)
//   add x6, x1, x7     <- in EX, must see the younger x1
//
// Distance 3 and beyond needs no forwarding: by then the producer has
// passed WB and the register file's internal write-to-read bypass has
// already made the value visible to the ID read ports.
//
// FORWARD_EN = 0 forces both selects to FWD_REG, which turns the network
// off for the stall-only configuration used in the CPI comparison.  The
// muxes remain in the datapath but become constant-selected, so synthesis
// optimises them away and the area figures stay honest.
//==========================================================================
`include "defines.vh"

module forwarding_unit #(
    parameter FORWARD_EN = 1
) (
    // source registers of the instruction in EX
    input  wire [4:0]            ex_rs1_addr,
    input  wire [4:0]            ex_rs2_addr,

    // instruction in MEM (EX/MEM register)
    input  wire                  mem_valid,
    input  wire                  mem_reg_write,
    input  wire [4:0]            mem_rd_addr,

    // instruction in WB (MEM/WB register)
    input  wire                  wb_valid,
    input  wire                  wb_reg_write,
    input  wire [4:0]            wb_rd_addr,

    output reg  [1:0]            fwd_a,
    output reg  [1:0]            fwd_b
);

    wire mem_can_fwd = mem_valid & mem_reg_write & (mem_rd_addr != 5'd0);
    wire wb_can_fwd  = wb_valid  & wb_reg_write  & (wb_rd_addr  != 5'd0);

    always @(*) begin
        // ---- operand A (rs1) ----
        if (!FORWARD_EN)
            fwd_a = `FWD_REG;
        else if (mem_can_fwd && (mem_rd_addr == ex_rs1_addr))
            fwd_a = `FWD_MEM;                 // younger producer wins
        else if (wb_can_fwd && (wb_rd_addr == ex_rs1_addr))
            fwd_a = `FWD_WB;
        else
            fwd_a = `FWD_REG;

        // ---- operand B (rs2) ----
        if (!FORWARD_EN)
            fwd_b = `FWD_REG;
        else if (mem_can_fwd && (mem_rd_addr == ex_rs2_addr))
            fwd_b = `FWD_MEM;
        else if (wb_can_fwd && (wb_rd_addr == ex_rs2_addr))
            fwd_b = `FWD_WB;
        else
            fwd_b = `FWD_REG;
    end

endmodule
