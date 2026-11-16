//==========================================================================
// wb_stage.v - Stage 5: write back
//
// Owner: Member D (Back end)
//
// Selects the value written into the register file and gates the write
// enable.
//
//   mem_to_reg = WB_MEM -> the word loaded by lw
//   mem_to_reg = WB_ALU -> the ALU result (add, sub, addi)
//
// wb_data is also the MEM/WB forwarding source consumed by the forwarding
// unit in EX.  Driving the forward path from the output of this mux, and
// not from the raw alu_result or mem_data fields, means the forwarded
// value is by construction identical to the value being written to the
// register file.  If the two were computed separately, a load could
// forward its ALU result (the address) instead of the loaded data - a
// classic and very confusing bug, because the address is a plausible
// looking number.
//
// reg_write is ANDed with valid for the same defensive reason as the
// store enable in mem_stage.v: a flushed or bubble slot must never alter
// architectural state.
//==========================================================================
`include "defines.vh"

module wb_stage (
    input  wire                  valid,
    input  wire                  reg_write,
    input  wire                  mem_to_reg,
    input  wire [`XLEN-1:0]      alu_result,
    input  wire [`XLEN-1:0]      mem_data,
    input  wire [4:0]            rd_addr_in,

    output wire [`XLEN-1:0]      wb_data,
    output wire                  wb_we,
    output wire [4:0]            wb_rd_addr
);

    assign wb_data    = (mem_to_reg == `WB_MEM) ? mem_data : alu_result;
    assign wb_we      = reg_write & valid;
    assign wb_rd_addr = rd_addr_in;

endmodule
