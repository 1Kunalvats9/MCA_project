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
//
//--------------------------------------------------------------------------
// Why continuous assignments and not always @(*)
//--------------------------------------------------------------------------
// This logic was originally an always @(*) block with the FORWARD_EN test
// inside it.  That is correct for FORWARD_EN = 1, but for FORWARD_EN = 0
// the block constant-folds to two literal assignments with no signals on
// any right-hand side.  An always @(*) with nothing to be sensitive to
// NEVER TRIGGERS, so fwd_a and fwd_b stayed X for the entire simulation.
//
// The stall-only configuration still produced correct results, but only
// by accident: a case statement with an X selector matches no explicit
// item and falls through to `default`, which happened to be the right
// answer (use the register file value).  Every test passed, so nothing
// drew attention to it until iverilog's -Wimplicit/-Wall was enabled and
// reported "@* found no sensitivities so it will never trigger".
//
// Continuous assignments have no sensitivity list to be empty, so both
// outputs are properly driven to FWD_REG in that configuration instead of
// being left undefined.  Synthesis was never affected - Yosys and Vivado
// both constant-fold the parameter - so this changes simulation hygiene,
// not hardware, and the measured numbers are unchanged.
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

    output wire [1:0]            fwd_a,
    output wire [1:0]            fwd_b
);

    wire mem_can_fwd = mem_valid & mem_reg_write & (mem_rd_addr != 5'd0);
    wire wb_can_fwd  = wb_valid  & wb_reg_write  & (wb_rd_addr  != 5'd0);

    // Enable term folded in per path, so that with FORWARD_EN = 0 every
    // condition is a constant 0 and both selects are a constant FWD_REG.
    wire en = (FORWARD_EN != 0);

    // ---- operand A (rs1) ----
    wire a_from_mem = en & mem_can_fwd & (mem_rd_addr == ex_rs1_addr);
    wire a_from_wb  = en & wb_can_fwd  & (wb_rd_addr  == ex_rs1_addr);

    // ---- operand B (rs2) ----
    wire b_from_mem = en & mem_can_fwd & (mem_rd_addr == ex_rs2_addr);
    wire b_from_wb  = en & wb_can_fwd  & (wb_rd_addr  == ex_rs2_addr);

    // EX/MEM is tested first: it is the younger producer and its write
    // happens later in program order.
    assign fwd_a = a_from_mem ? `FWD_MEM :
                   a_from_wb  ? `FWD_WB  :
                                `FWD_REG;

    assign fwd_b = b_from_mem ? `FWD_MEM :
                   b_from_wb  ? `FWD_WB  :
                                `FWD_REG;

endmodule
