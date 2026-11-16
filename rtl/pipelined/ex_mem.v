//==========================================================================
// ex_mem.v - EX/MEM pipeline register
//
// Owner: Member C (Execute stage)
//
// Carries the ALU result (the data value for add/sub/addi, the effective
// address for lw/sw), the store data, rd, and the control bits that the
// MEM and WB stages still need.
//
// store_data is taken AFTER the rs2 forwarding mux in EX, so what arrives
// here is already the architecturally correct value.  Forwarding store
// data in EX rather than in MEM means the MEM stage needs no forwarding
// logic at all.
//
// Control bits that have been consumed (alu_src, alu_ctrl, branch,
// branch_ne) are deliberately not propagated: once EX is done with them,
// carrying them further would only widen the register and invite a later
// stage to misuse them.
//==========================================================================
`include "defines.vh"

module ex_mem (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  bubble,

    input  wire [`XLEN-1:0]      in_alu_result,
    input  wire [`XLEN-1:0]      in_store_data,
    input  wire [4:0]            in_rd_addr,
    input  wire [31:0]           in_instr,
    input  wire                  in_valid,
    input  wire                  in_reg_write,
    input  wire                  in_mem_read,
    input  wire                  in_mem_write,
    input  wire                  in_mem_to_reg,

    output reg  [`XLEN-1:0]      out_alu_result,
    output reg  [`XLEN-1:0]      out_store_data,
    output reg  [4:0]            out_rd_addr,
    output reg  [31:0]           out_instr,
    output reg                   out_valid,
    output reg                   out_reg_write,
    output reg                   out_mem_read,
    output reg                   out_mem_write,
    output reg                   out_mem_to_reg
);

    always @(posedge clk) begin
        if (rst || bubble) begin
            out_alu_result <= {`XLEN{1'b0}};
            out_store_data <= {`XLEN{1'b0}};
            out_rd_addr    <= 5'd0;
            out_instr      <= 32'h00000000;
            out_valid      <= 1'b0;
            out_reg_write  <= 1'b0;
            out_mem_read   <= 1'b0;
            out_mem_write  <= 1'b0;
            out_mem_to_reg <= `WB_ALU;
        end else begin
            out_alu_result <= in_alu_result;
            out_store_data <= in_store_data;
            out_rd_addr    <= in_rd_addr;
            out_instr      <= in_instr;
            out_valid      <= in_valid;
            out_reg_write  <= in_reg_write;
            out_mem_read   <= in_mem_read;
            out_mem_write  <= in_mem_write;
            out_mem_to_reg <= in_mem_to_reg;
        end
    end

endmodule
