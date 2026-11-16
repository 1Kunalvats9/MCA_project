//==========================================================================
// regfile.v - 32 x 32-bit architectural register file
//
// Owner: Member B (Decode stage)
//
// Two combinational read ports, one synchronous write port.
//
// Two details that matter for the pipeline:
//
//  1. x0 is hardwired to zero.  Reads of x0 always return 0 and writes to
//     x0 are discarded, so the hazard units never have to special-case it
//     downstream (they still suppress forwarding from rd==x0, because
//     forwarding a discarded write would be wrong).
//
//  2. Internal write-to-read bypass, enabled by WB_BYPASS.  When a read
//     address matches the address being written in the same cycle, the
//     write data is returned directly.  This removes the WB -> ID hazard
//     entirely, so the forwarding unit only has to cover EX/MEM and
//     MEM/WB.  Without it the pipeline would need a third forwarding
//     source or an extra stall.
//
//     WB_BYPASS MUST BE 0 FOR THE SINGLE-CYCLE CORE.
//
//     In the pipelined core the write comes from an OLDER instruction
//     sitting in WB, so the bypass connects two different instructions
//     and is exactly what is wanted.  In the single-cycle core the read
//     and the write belong to the SAME instruction, and the bypass closes
//     a combinational loop:
//
//         rs1_data -> ALU -> wb_data -> (bypass) -> rs1_data
//
//     Any instruction whose rd equals one of its own source registers,
//     for example "add x2, x2, x4" in programs/array_sum.s, makes that
//     loop oscillate and the simulator never settles.  The single-cycle
//     core does not need the bypass at all: its write lands on the clock
//     edge and the next instruction reads it in the next cycle.
//
//     This was found during bring-up: the first three benchmarks passed
//     because none of them reuses a destination as a source, and
//     array_sum was the first program to trip it.  It is written up in
//     the report as a worked example of why the two cores cannot simply
//     share every submodule unchanged.
//==========================================================================
`include "defines.vh"

module regfile #(
    parameter WB_BYPASS = 1
) (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [4:0]            rs1_addr,
    input  wire [4:0]            rs2_addr,
    output wire [`XLEN-1:0]      rs1_data,
    output wire [`XLEN-1:0]      rs2_data,

    input  wire                  we,
    input  wire [4:0]            rd_addr,
    input  wire [`XLEN-1:0]      rd_data
);

    reg [`XLEN-1:0] regs [0:31];
    integer i;

    // Writes to x0 are discarded.
    wire write_en = we & (rd_addr != 5'd0);

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= {`XLEN{1'b0}};
        end else if (write_en) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Combinational read, with the same-cycle write bypass only when
    // WB_BYPASS is set (see note 2 in the header).
    wire bypass1 = (WB_BYPASS != 0) && write_en && (rs1_addr == rd_addr);
    wire bypass2 = (WB_BYPASS != 0) && write_en && (rs2_addr == rd_addr);

    assign rs1_data = (rs1_addr == 5'd0) ? {`XLEN{1'b0}} :
                      bypass1            ? rd_data       :
                                           regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? {`XLEN{1'b0}} :
                      bypass2            ? rd_data       :
                                           regs[rs2_addr];

endmodule
