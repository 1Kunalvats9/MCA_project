//==========================================================================
// imem.v - Instruction memory (read-only)
//
// Owner: Member A (Fetch stage)
//
// 1024 x 32-bit words, combinational read.  Initialised from a hex image
// produced by tools/asm.py.  Addresses are byte addresses; bits [1:0] are
// dropped because every instruction is word aligned.
//
// Unwritten locations read as 32'h00000000.  That word is not a legal
// RISC-V instruction, and both cores treat it as a simulation-only HALT:
// fetching it stops the program counter and stops injecting valid
// instructions into the pipeline.  Every benchmark therefore terminates
// simply by running off the end of its own code, which lets the testbench
// count retired instructions exactly, with no need to know the program
// length in advance.  See docs/REPORT.md for the halt convention.
//==========================================================================
`include "defines.vh"

module imem #(
    parameter HEXFILE = ""
) (
    input  wire [`XLEN-1:0]      addr,
    output wire [31:0]           instr
);

    reg [31:0] mem [0:`MEM_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < `MEM_WORDS; i = i + 1)
            mem[i] = 32'h00000000;         // HALT (see note above)
        if (HEXFILE != "")
            $readmemh(HEXFILE, mem);
    end

    wire [`MEM_ADDR_BITS-1:0] word_addr = addr[`MEM_ADDR_BITS+1:2];

    assign instr = mem[word_addr];

endmodule
