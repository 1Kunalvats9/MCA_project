//==========================================================================
// dmem.v - Data memory
//
// Owner: Member D (Back end / MEM stage)
//
//--------------------------------------------------------------------------
// Organisation
//--------------------------------------------------------------------------
// 1024 x 32-bit words = 4 KiB, word addressed internally.  The datapath
// hands over a byte address (the ALU result of base + offset) and this
// module drops the low two bits, so only naturally aligned word accesses
// are supported.  That is sufficient because the instruction subset has
// lw/sw and no byte or half-word accesses.
//
//--------------------------------------------------------------------------
// Read timing: why the read is combinational
//--------------------------------------------------------------------------
// In this five-stage pipeline the MEM stage occupies exactly one cycle and
// the loaded value must be captured by the MEM/WB register at the end of
// that same cycle.  A combinational (asynchronous) read gives:
//
//      posedge          posedge
//        |                 |
//        | EX/MEM holds    | MEM/WB captures
//        | addr, so addr   | rdata
//        | is stable for   |
//        | the whole cycle |
//
// If the read were registered instead, rdata would only appear one cycle
// later, i.e. during WB, and the MEM/WB register would latch stale data.
// A registered-read memory would therefore force either a second memory
// stage or a mandatory one-cycle stall on every load.
//
// Consequence for synthesis (documented as a known limitation in the
// report): an asynchronous-read memory maps to distributed LUT RAM rather
// than to a block RAM on an FPGA, because block RAMs have a registered
// read port.  At 1024 words this costs LUTs but still fits comfortably on
// an Artix-7.  Moving to block RAM would require restructuring the MEM
// stage, which is out of scope here.
//
//--------------------------------------------------------------------------
// Write timing
//--------------------------------------------------------------------------
// Writes are synchronous on the rising edge and gated by we.  Because the
// hazard and flush logic clears the control bits of a squashed or bubble
// instruction, we is never asserted for an instruction that must not
// commit.  This is the property that keeps a flushed sw from corrupting
// memory, and it is the reason the control bits (and not just the data)
// are cleared when a bubble is inserted.
//
// Store data arrives already forwarded.  The forwarding mux for rs2 sits
// in EX, not in MEM, so by the time a value reaches this module it is the
// architecturally correct one.  Verified by the store-forward case in
// tb_hazards.v.
//
// No read/write ordering hazard exists inside a single-ported memory used
// by one stage: only one instruction is in MEM at a time, so a sw followed
// by a lw of the same address is separated by at least one cycle and the
// write has already committed before the read is issued.
//==========================================================================
`include "defines.vh"

module dmem #(
    parameter HEXFILE = ""
) (
    input  wire                  clk,

    input  wire [`XLEN-1:0]      addr,      // byte address from the ALU
    input  wire                  we,        // store enable  (sw)
    input  wire                  re,        // load  enable  (lw)
    input  wire [`XLEN-1:0]      wdata,     // store data (already forwarded)
    output wire [`XLEN-1:0]      rdata
);

    reg [`XLEN-1:0] mem [0:`MEM_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < `MEM_WORDS; i = i + 1)
            mem[i] = {`XLEN{1'b0}};
        if (HEXFILE != "")
            $readmemh(HEXFILE, mem);
    end

    wire [`MEM_ADDR_BITS-1:0] word_addr = addr[`MEM_ADDR_BITS+1:2];

    // Synchronous write.
    always @(posedge clk) begin
        if (we)
            mem[word_addr] <= wdata;
    end

    // Combinational read.  Returns zero when no load is in progress so
    // that waveforms show a clean value instead of whatever word the
    // address bus happens to point at.
    assign rdata = re ? mem[word_addr] : {`XLEN{1'b0}};

    //----------------------------------------------------------------------
    // Note on inspecting memory from a testbench
    //
    // There is deliberately no debug task or peek function here.  Earlier
    // versions had both, carrying a $display, and neither was ever used:
    // the testbenches read this array hierarchically instead
    // (dut.u_mem.u_dmem.mem[i] in the pipelined cores,
    // dut.u_dmem.mem[i] in the single-cycle core), which is what
    // tb_core.v's signature dump and tb_hazards.v's check_mem task do.
    //
    // They were removed because a task containing $display sits inside a
    // module that real FPGA synthesis has to read, and dead
    // simulation-only code in a synthesised module is an avoidable risk
    // for the Vivado flow.  Everything above this point is synthesisable:
    // the one remaining initial block is a $readmemh memory
    // initialisation, which Vivado supports for RAM inference.
    //----------------------------------------------------------------------

endmodule
