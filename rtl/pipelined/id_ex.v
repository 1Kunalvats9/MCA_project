//==========================================================================
// id_ex.v - ID/EX pipeline register
//
// Owner: Member B (Decode stage)
//
// The widest pipeline register: it carries the two register operands, the
// immediate, the PC (for the branch target adder in EX), the register
// addresses (rs1/rs2 for forwarding comparisons, rd for the write-back
// path) and the entire control bundle generated in ID.
//
// bubble: insert a NOP.  Asserted when the hazard unit stalls (the
// instruction stays in ID, so EX must be given something harmless) or
// when a taken branch is flushing the wrongly-fetched instructions.
//
// A bubble clears every control bit, not just the valid bit.  This is the
// single most important line in the whole hazard design: reg_write,
// mem_write, mem_read and branch must all go to zero so the bubble cannot
// write a register, write memory, or redirect the PC.  Zeroing valid alone
// would leave mem_write asserted and a flushed store would corrupt memory.
//==========================================================================
`include "defines.vh"

module id_ex (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  bubble,

    // data
    input  wire [`XLEN-1:0]      in_pc,
    input  wire [`XLEN-1:0]      in_rs1_data,
    input  wire [`XLEN-1:0]      in_rs2_data,
    input  wire [`XLEN-1:0]      in_imm,
    input  wire [4:0]            in_rs1_addr,
    input  wire [4:0]            in_rs2_addr,
    input  wire [4:0]            in_rd_addr,
    input  wire [31:0]           in_instr,
    input  wire                  in_valid,
    input  wire                  in_predicted_taken,
    // control
    input  wire                  in_reg_write,
    input  wire                  in_alu_src,
    input  wire [1:0]            in_alu_ctrl,
    input  wire                  in_mem_read,
    input  wire                  in_mem_write,
    input  wire                  in_mem_to_reg,
    input  wire                  in_branch,
    input  wire                  in_branch_ne,

    // data
    output reg  [`XLEN-1:0]      out_pc,
    output reg  [`XLEN-1:0]      out_rs1_data,
    output reg  [`XLEN-1:0]      out_rs2_data,
    output reg  [`XLEN-1:0]      out_imm,
    output reg  [4:0]            out_rs1_addr,
    output reg  [4:0]            out_rs2_addr,
    output reg  [4:0]            out_rd_addr,
    output reg  [31:0]           out_instr,
    output reg                   out_valid,
    output reg                   out_predicted_taken,
    // control
    output reg                   out_reg_write,
    output reg                   out_alu_src,
    output reg  [1:0]            out_alu_ctrl,
    output reg                   out_mem_read,
    output reg                   out_mem_write,
    output reg                   out_mem_to_reg,
    output reg                   out_branch,
    output reg                   out_branch_ne
);

    always @(posedge clk) begin
        if (rst || bubble) begin
            out_pc         <= {`XLEN{1'b0}};
            out_rs1_data   <= {`XLEN{1'b0}};
            out_rs2_data   <= {`XLEN{1'b0}};
            out_imm        <= {`XLEN{1'b0}};
            out_rs1_addr   <= 5'd0;
            out_rs2_addr   <= 5'd0;
            out_rd_addr    <= 5'd0;
            out_instr      <= 32'h00000000;
            out_valid      <= 1'b0;
            // A bubble carries no prediction: with valid low it can never
            // be counted as a mispredict in EX.
            out_predicted_taken <= 1'b0;
            // every control bit cleared - see header comment
            out_reg_write  <= 1'b0;
            out_alu_src    <= 1'b0;
            out_alu_ctrl   <= `ALU_ADD;
            out_mem_read   <= 1'b0;
            out_mem_write  <= 1'b0;
            out_mem_to_reg <= `WB_ALU;
            out_branch     <= 1'b0;
            out_branch_ne  <= 1'b0;
        end else begin
            out_pc         <= in_pc;
            out_rs1_data   <= in_rs1_data;
            out_rs2_data   <= in_rs2_data;
            out_imm        <= in_imm;
            out_rs1_addr   <= in_rs1_addr;
            out_rs2_addr   <= in_rs2_addr;
            out_rd_addr    <= in_rd_addr;
            out_instr      <= in_instr;
            out_valid      <= in_valid;
            out_predicted_taken <= in_predicted_taken;
            out_reg_write  <= in_reg_write;
            out_alu_src    <= in_alu_src;
            out_alu_ctrl   <= in_alu_ctrl;
            out_mem_read   <= in_mem_read;
            out_mem_write  <= in_mem_write;
            out_mem_to_reg <= in_mem_to_reg;
            out_branch     <= in_branch;
            out_branch_ne  <= in_branch_ne;
        end
    end

endmodule
