//==========================================================================
// branch_cmp.v - Branch condition comparator
//
// Owner: Member C (Execute stage)
//
// Compares the two (already forwarded) register operands and reports
// whether the branch should be taken.  Kept separate from the ALU so the
// comparison runs in parallel with address arithmetic.
//
//   branch    = 1 when the instruction in EX is a beq or bne
//   branch_ne = 0 for beq, 1 for bne
//==========================================================================
`include "defines.vh"

module branch_cmp (
    input  wire                  branch,
    input  wire                  branch_ne,
    input  wire [`XLEN-1:0]      rs1_data,
    input  wire [`XLEN-1:0]      rs2_data,
    output wire                  take_branch
);

    wire equal = (rs1_data == rs2_data);

    assign take_branch = branch & (branch_ne ? ~equal : equal);

endmodule
