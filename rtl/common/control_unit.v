//==========================================================================
// control_unit.v - Main control decoder
//
// Owner: Member B (Decode stage)
//
// Purely combinational decode of opcode / funct3 / funct7 into the control
// bundle that travels down the pipeline inside the pipeline registers.
//
// Critical pipeline rule: control signals are generated ONCE, here in ID,
// and then carried alongside the data through ID/EX, EX/MEM and MEM/WB.
// They are never recomputed in a later stage.  Recomputing them from a
// later stage's instruction register is the classic bug that makes control
// apply to the wrong instruction.
//
// Control bundle:
//   reg_write   : the instruction writes rd
//   alu_src     : 0 = second ALU operand is rs2, 1 = it is the immediate
//   alu_ctrl    : ALU_ADD or ALU_SUB
//   mem_read    : load
//   mem_write   : store
//   mem_to_reg  : WB_ALU or WB_MEM - selects the write-back source
//   branch      : this is a conditional branch
//   branch_ne   : 0 = beq, 1 = bne
//   uses_rs1    : the instruction actually reads rs1
//   uses_rs2    : the instruction actually reads rs2
//   illegal     : nothing matched (debug / simulation only)
//
// uses_rs1 / uses_rs2 exist for the hazard unit.  Without them the hazard
// detector would stall on a register number that happens to sit in the
// rs2 field of an addi or lw, where that field is part of the immediate
// and is never read.  Those are false dependencies and stalling on them
// silently inflates CPI.
//==========================================================================
`include "defines.vh"

module control_unit (
    input  wire [6:0]            opcode,
    input  wire [2:0]            funct3,
    input  wire [6:0]            funct7,

    output reg                   reg_write,
    output reg                   alu_src,
    output reg  [1:0]            alu_ctrl,
    output reg                   mem_read,
    output reg                   mem_write,
    output reg                   mem_to_reg,
    output reg                   branch,
    output reg                   branch_ne,
    output reg                   uses_rs1,
    output reg                   uses_rs2,
    output reg                   illegal
);

    always @(*) begin
        // Safe defaults: an unrecognised instruction behaves as a NOP and
        // in particular never writes a register or memory.
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        alu_ctrl   = `ALU_ADD;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = `WB_ALU;
        branch     = 1'b0;
        branch_ne  = 1'b0;
        uses_rs1   = 1'b0;
        uses_rs2   = 1'b0;
        illegal    = 1'b0;

        case (opcode)
            //---------------------------------------------------- add / sub
            `OP_RTYPE: begin
                reg_write  = 1'b1;
                alu_src    = 1'b0;                 // rs2
                mem_to_reg = `WB_ALU;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                if (funct3 == `F3_ADD_SUB)
                    alu_ctrl = (funct7 == `F7_SUB) ? `ALU_SUB : `ALU_ADD;
                else begin
                    alu_ctrl = `ALU_ADD;
                    illegal  = 1'b1;
                end
            end

            //-------------------------------------------------------- addi
            `OP_IARITH: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;                 // immediate
                alu_ctrl   = `ALU_ADD;
                mem_to_reg = `WB_ALU;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b0;                 // instr[24:20] is immediate
                if (funct3 != `F3_ADD_SUB)
                    illegal = 1'b1;
            end

            //---------------------------------------------------------- lw
            `OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;                 // base + offset
                alu_ctrl   = `ALU_ADD;
                mem_read   = 1'b1;
                mem_to_reg = `WB_MEM;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b0;                 // instr[24:20] is immediate
                if (funct3 != `F3_LW_SW)
                    illegal = 1'b1;
            end

            //---------------------------------------------------------- sw
            `OP_STORE: begin
                reg_write  = 1'b0;                 // stores write no register
                alu_src    = 1'b1;                 // base + offset
                alu_ctrl   = `ALU_ADD;
                mem_write  = 1'b1;
                uses_rs1   = 1'b1;                 // base address
                uses_rs2   = 1'b1;                 // store data
                if (funct3 != `F3_LW_SW)
                    illegal = 1'b1;
            end

            //--------------------------------------------------- beq / bne
            `OP_BRANCH: begin
                reg_write  = 1'b0;
                alu_src    = 1'b0;
                alu_ctrl   = `ALU_SUB;             // unused, kept meaningful
                branch     = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                case (funct3)
                    `F3_BEQ: branch_ne = 1'b0;
                    `F3_BNE: branch_ne = 1'b1;
                    default: begin
                        branch    = 1'b0;
                        illegal   = 1'b1;
                    end
                endcase
            end

            default: illegal = 1'b1;
        endcase
    end

endmodule
