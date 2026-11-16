//==========================================================================
// mem_stage.v - Stage 4: data memory access
//
// Owner: Member D (Back end)
//
// A thin wrapper around the data memory.  The only logic here is the
// gating of the write enable with the valid bit.
//
// we = mem_write & valid is a safety belt rather than a necessity: the
// bubble logic in ID/EX and EX/MEM already clears mem_write for any slot
// that must not commit, so mem_write should never be high while valid is
// low.  The extra AND is one gate and it guarantees that a single missed
// clear somewhere upstream cannot silently corrupt memory - which would
// be the hardest class of bug to find in this design, because the wrong
// value only shows up much later when something loads it back.
//
// Loads are unconditional in the sense that re is just mem_read: a read
// has no side effect, so there is nothing to protect against.
//==========================================================================
`include "defines.vh"

module mem_stage #(
    parameter DMEM_HEX = ""
) (
    input  wire                  clk,
    input  wire                  valid,

    input  wire [`XLEN-1:0]      addr,        // ALU result = base + offset
    input  wire                  mem_read,
    input  wire                  mem_write,
    input  wire [`XLEN-1:0]      store_data,

    output wire [`XLEN-1:0]      mem_data
);

    wire we = mem_write & valid;
    wire re = mem_read;

    dmem #(.HEXFILE(DMEM_HEX)) u_dmem (
        .clk   (clk),
        .addr  (addr),
        .we    (we),
        .re    (re),
        .wdata (store_data),
        .rdata (mem_data)
    );

endmodule
