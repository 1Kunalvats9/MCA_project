//==========================================================================
// branch_predictor.v - Branch History Table of 2-bit saturating counters
//
// Owner: Member A (Front end), reviewed by Member D (hazard logic)
//
//--------------------------------------------------------------------------
// Why this exists
//--------------------------------------------------------------------------
// With static not-taken prediction every TAKEN branch costs two flushed
// slots, and the performance analysis showed that penalty to be two
// thirds of the pipeline's whole overhead on loop code (vecsum64: 126
// flushed slots against 64 load-use bubbles).  Loop branches are taken
// almost every time, so static not-taken is wrong almost every time.  A
// table that remembers what each branch did last gets them right.
//
//--------------------------------------------------------------------------
// The 2-bit saturating counter
//--------------------------------------------------------------------------
// One counter per table entry, updated when a branch resolves in EX:
//
//      taken ->            taken ->           taken ->
//   00 --------------> 01 ------------> 10 ------------> 11
//  strongly  <-------- weakly <-------- weakly <-------- strongly
//  NOT TAKEN  not taken  NT   not taken   T    not taken  TAKEN
//
// The prediction is the TOP BIT: predict taken for 10 and 11.
//
// Two bits rather than one because a single bit mispredicts twice for
// every loop: once on the final (not-taken) iteration, and then again on
// the first iteration of the next entry into the loop, because the single
// bit was flipped by that final iteration.  A 2-bit counter absorbs one
// anomalous outcome without changing its prediction, so a loop executed
// repeatedly mispredicts only on its last iteration.
//
//--------------------------------------------------------------------------
// Initial state
//--------------------------------------------------------------------------
// All entries reset to 01 (weakly not taken).  That makes the FIRST
// prediction for any branch identical to what the static not-taken
// configuration would do, so the comparison between the two isolates the
// effect of learning and nothing else.
//
//--------------------------------------------------------------------------
// Indexing, and aliasing
//--------------------------------------------------------------------------
// Indexed by PC[INDEX_BITS+1:2] - the low instruction-address bits, with
// the two always-zero byte-offset bits dropped.  There is NO tag, so two
// branches whose addresses differ only in higher bits share an entry and
// interfere with each other.  This is normal for a BHT of this kind: a
// wrong prediction is only a performance loss, never a correctness
// problem, because EX always checks the real outcome.  64 entries covers
// 256 bytes of code, which is more than any benchmark here, so no
// aliasing actually occurs in the measurements - stated as a limitation
// rather than claimed as a result.
//
//--------------------------------------------------------------------------
// No branch target buffer is needed
//--------------------------------------------------------------------------
// Predictors usually need a BTB to supply the target address at fetch
// time, because the instruction has not been decoded yet.  This design
// does not, because the instruction memory read is combinational: the
// instruction word is already available in IF, so the branch target can
// be computed there directly with an adder and a B-format immediate
// decoder.  That trades a BTB for an extra adder in the IF stage - which
// does lengthen the IF critical path, and the synthesis section reports
// the cost.
//
//--------------------------------------------------------------------------
// Read during write
//--------------------------------------------------------------------------
// The read port (IF) and the write port (EX) can address the same entry
// in the same cycle, in which case the read returns the OLD counter
// value.  No bypass is provided.  The effect is bounded and tiny: it can
// only happen when two dynamic instances of the same branch are three
// cycles apart, and the worst case is one extra mispredict.  Adding a
// bypass would put the update logic on the IF critical path, which is
// already the path this feature lengthens.
//==========================================================================
`include "defines.vh"

module branch_predictor #(
    parameter INDEX_BITS = 6           // 64 entries
) (
    input  wire                  clk,
    input  wire                  rst,

    // ---- prediction port, read in IF ----
    input  wire [`XLEN-1:0]      if_pc,
    output wire                  predict_taken,

    // ---- update port, written from EX when a branch resolves ----
    input  wire                  update_en,
    input  wire [`XLEN-1:0]      update_pc,
    input  wire                  update_taken
);

    localparam ENTRIES = (1 << INDEX_BITS);

    reg [1:0] bht [0:ENTRIES-1];
    integer i;

    wire [INDEX_BITS-1:0] if_index     = if_pc[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] update_index = update_pc[INDEX_BITS+1:2];

    // The prediction is the counter's top bit: 10 and 11 predict taken.
    assign predict_taken = bht[if_index][1];

    wire [1:0] cur = bht[update_index];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1)
                bht[i] <= `BHT_WEAK_NT;        // 01, see header
        end else if (update_en) begin
            if (update_taken)
                bht[update_index] <= (cur == `BHT_STRONG_T) ? `BHT_STRONG_T
                                                            : cur + 2'b01;
            else
                bht[update_index] <= (cur == `BHT_STRONG_NT) ? `BHT_STRONG_NT
                                                             : cur - 2'b01;
        end
    end

endmodule
