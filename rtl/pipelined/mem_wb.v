//==========================================================================
// mem_wb.v - MEM/WB pipeline register
//
// Owner: Member D (Back end)
//
//--------------------------------------------------------------------------
// What it carries and why
//--------------------------------------------------------------------------
// The write-back stage has to choose between two possible results, so both
// have to arrive here:
//
//   alu_result - the value for add / sub / addi
//   mem_data   - the word returned by the data memory for lw
//
// An alternative design muxes the two sources at the END of MEM and
// carries a single wb_data field, which saves 32 flip-flops.  This design
// deliberately carries both and muxes in WB instead, for two reasons:
//
//   1. The forwarding unit forwards from MEM/WB.  Having both fields here
//      means the forward path can select exactly the same value WB will
//      write, using the same mem_to_reg bit, with no duplicated mux.
//   2. In a waveform you can see both candidate values side by side, which
//      makes a mis-selected write-back source obvious instead of subtle.
//
// The 32 extra flip-flops are reported in the synthesis section as the
// cost of that choice.
//
//--------------------------------------------------------------------------
// Why this register has no stall input
//--------------------------------------------------------------------------
// Stalls in this pipeline are only ever inserted in front of EX: the
// hazard unit holds IF and ID and injects a bubble into ID/EX.  Nothing
// downstream of EX ever has to wait, because no instruction in MEM or WB
// can be blocked once it has started (the memory answers in a single
// cycle).  So EX/MEM and MEM/WB only need a bubble input, used by reset
// and by nothing else in the current design.  If a multi-cycle memory were
// ever added, this is the register that would need a hold input, and the
// hazard unit would need a back-pressure path.
//==========================================================================
`include "defines.vh"

module mem_wb (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  bubble,

    input  wire [`XLEN-1:0]      in_alu_result,
    input  wire [`XLEN-1:0]      in_mem_data,
    input  wire [4:0]            in_rd_addr,
    input  wire [31:0]           in_instr,
    input  wire                  in_valid,
    input  wire                  in_reg_write,
    input  wire                  in_mem_to_reg,

    output reg  [`XLEN-1:0]      out_alu_result,
    output reg  [`XLEN-1:0]      out_mem_data,
    output reg  [4:0]            out_rd_addr,
    output reg  [31:0]           out_instr,
    output reg                   out_valid,
    output reg                   out_reg_write,
    output reg                   out_mem_to_reg
);

    always @(posedge clk) begin
        if (rst || bubble) begin
            out_alu_result <= {`XLEN{1'b0}};
            out_mem_data   <= {`XLEN{1'b0}};
            out_rd_addr    <= 5'd0;
            out_instr      <= 32'h00000000;
            out_valid      <= 1'b0;
            out_reg_write  <= 1'b0;
            out_mem_to_reg <= `WB_ALU;
        end else begin
            out_alu_result <= in_alu_result;
            out_mem_data   <= in_mem_data;
            out_rd_addr    <= in_rd_addr;
            out_instr      <= in_instr;
            out_valid      <= in_valid;
            out_reg_write  <= in_reg_write;
            out_mem_to_reg <= in_mem_to_reg;
        end
    end

endmodule
