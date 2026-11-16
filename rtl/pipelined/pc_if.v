//==========================================================================
// pc_if.v - Stage 1: program counter and instruction fetch
//
// Owner: Member A (Front end)
//
//--------------------------------------------------------------------------
// Next-PC selection, in priority order
//--------------------------------------------------------------------------
//   1. redirect  - EX found the prediction wrong.  Take redirect_target,
//                  which is the branch target on a mispredicted-not-taken
//                  and pc+4 on a mispredicted-taken.  This must win over
//                  a stall: the stalled instruction is on the wrong path
//                  and is about to be discarded anyway.
//   2. stall / halt - hold the PC.
//   3. predict_taken - the predictor says this branch is taken, so fetch
//                  the computed target next.
//   4. otherwise - pc + 4.
//
//--------------------------------------------------------------------------
// Prediction, and why the target can be computed here
//--------------------------------------------------------------------------
// PREDICTOR = 0 : static not-taken.  predicted_taken is tied low, so
//                 case 3 never fires and every taken branch is a
//                 mispredict discovered in EX, costing two slots.
// PREDICTOR = 1 : the branch history table in branch_predictor.v decides.
//
// A predictor normally needs a branch target buffer, because at fetch
// time the instruction has not been decoded.  Here it does not: the
// instruction memory read is combinational, so `instr` is already
// available in this stage.  The opcode tells us it is a branch and a
// B-format immediate decoder plus one adder give the target directly.
//
// The cost of that convenience is real and is reported in the synthesis
// section: this stage now contains an immediate decoder and a 32-bit
// adder that it did not contain before, which lengthens the IF path.
//
// predicted_taken is gated with is_branch and with ~halt_fetch so that a
// stale table entry can never redirect a non-branch or a halt word.
//==========================================================================
`include "defines.vh"

module pc_if #(
    parameter IMEM_HEX  = "",
    parameter PREDICTOR = 0
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,

    // correction from EX
    input  wire                  redirect,
    input  wire [`XLEN-1:0]      redirect_target,

    // prediction lookup (raw table output; gating happens here)
    input  wire                  predict_taken_raw,

    output wire [`XLEN-1:0]      pc,
    output wire [31:0]           instr,
    output wire                  if_valid,
    output wire                  halt_fetch,
    output wire                  if_is_branch,
    output wire                  predicted_taken
);

    reg [`XLEN-1:0] pc_reg;
    wire [`XLEN-1:0] pc_plus4 = pc_reg + 32'd4;
    wire [`XLEN-1:0] pc_next;

    imem #(.HEXFILE(IMEM_HEX)) u_imem (
        .addr  (pc_reg),
        .instr (instr)
    );

    assign halt_fetch   = (instr == 32'h00000000);
    assign if_is_branch = (instr[6:0] == `OP_BRANCH);

    //---------------------------------------------------------- prediction
    // B-format immediate, decoded here so the target can be computed in
    // this stage instead of needing a branch target buffer.
    wire [`XLEN-1:0] imm_b;

    imm_gen u_imm_if (
        .instr (instr),
        .imm   (imm_b)
    );

    wire [`XLEN-1:0] predicted_target = pc_reg + imm_b;

    assign predicted_taken = (PREDICTOR != 0) ?
                             (if_is_branch & predict_taken_raw & ~halt_fetch)
                             : 1'b0;

    //------------------------------------------------------ next-PC select
    assign pc_next = redirect              ? redirect_target  :
                     (stall | halt_fetch)  ? pc_reg           :
                     predicted_taken       ? predicted_target :
                                             pc_plus4;

    always @(posedge clk) begin
        if (rst)
            pc_reg <= {`XLEN{1'b0}};
        else
            pc_reg <= pc_next;
    end

    assign pc       = pc_reg;
    assign if_valid = ~halt_fetch & ~rst;

endmodule
