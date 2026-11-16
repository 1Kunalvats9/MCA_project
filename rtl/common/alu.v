//==========================================================================
// alu.v - Arithmetic / Logic Unit
//
// Owner: Member C (Execute stage)
//
// Purely combinational.  Only ADD and SUB are needed by the supported
// instruction set:
//     add, addi, lw, sw   -> ADD   (lw/sw use it for base+offset)
//     sub                 -> SUB
// The zero flag is produced for completeness; branch decisions are taken
// by the dedicated comparator in branch_cmp.v rather than from this flag,
// so that a branch does not have to wait on the full ALU result path.
//==========================================================================
`include "defines.vh"

module alu (
    input  wire [1:0]            alu_ctrl,
    input  wire [`XLEN-1:0]      a,
    input  wire [`XLEN-1:0]      b,
    output reg  [`XLEN-1:0]      result,
    output wire                  zero
);

    always @(*) begin
        case (alu_ctrl)
            `ALU_ADD: result = a + b;
            `ALU_SUB: result = a - b;
            default:  result = a + b;   // defined behaviour on unused codes
        endcase
    end

    assign zero = (result == {`XLEN{1'b0}});

endmodule
