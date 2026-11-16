//==========================================================================
// imm_gen.v - Immediate generator / sign extender
//
// Owner: Member B (Decode stage)
//
// Extracts and sign-extends the immediate field.  The three formats in
// use scatter the immediate bits differently:
//
//   I-type (addi, lw) : imm[11:0] = instr[31:20]
//   S-type (sw)       : imm[11:0] = {instr[31:25], instr[11:7]}
//   B-type (beq, bne) : imm[12:1] = {instr[31], instr[7],
//                                    instr[30:25], instr[11:8]}, imm[0]=0
//
// B-type immediates are already scaled to bytes (the implicit low zero),
// so the branch target is simply pc + imm with no extra shift.
//==========================================================================
`include "defines.vh"

module imm_gen (
    input  wire [31:0]           instr,
    output reg  [`XLEN-1:0]      imm
);

    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            `OP_IARITH,
            `OP_LOAD:
                imm = {{20{instr[31]}}, instr[31:20]};

            `OP_STORE:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            `OP_BRANCH:
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};

            default:
                imm = {`XLEN{1'b0}};
        endcase
    end

endmodule
