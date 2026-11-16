//==========================================================================
// if_id.v - IF/ID pipeline register
//
// Owner: Member A (Front end)
//
// Carries the fetched instruction and its PC from IF into ID.
//
// Three control inputs, in priority order:
//
//   flush  - a branch resolved as taken in EX, so the instruction sitting
//            here was fetched from the wrong path.  Clear the register and
//            mark it invalid.  Clearing instr to the halt word (all zeros)
//            rather than leaving stale bits makes waveforms unambiguous.
//
//   stall  - a hazard in ID cannot be resolved by forwarding, so the
//            instruction here must be presented to ID again next cycle.
//            HOLD the current contents (do not clear, do not load).
//
//   (none) - load the new fetch.
//
// flush takes priority over stall: a stalled instruction on a mispredicted
// path must still be discarded.
//
// predicted_taken travels with the instruction it belongs to.  EX needs
// it to decide whether the prediction was right, and because it is held
// alongside the instruction it stays correct across a stall.
//
// The valid bit is what distinguishes a real instruction from a bubble.
// It is used for retired-instruction counting and to stop the hazard unit
// from reacting to an empty slot.
//==========================================================================
`include "defines.vh"

module if_id (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  stall,
    input  wire                  flush,

    input  wire [`XLEN-1:0]      in_pc,
    input  wire [31:0]           in_instr,
    input  wire                  in_valid,
    input  wire                  in_predicted_taken,

    output reg  [`XLEN-1:0]      out_pc,
    output reg  [31:0]           out_instr,
    output reg                   out_valid,
    output reg                   out_predicted_taken
);

    always @(posedge clk) begin
        if (rst || flush) begin
            out_pc              <= {`XLEN{1'b0}};
            out_instr           <= 32'h00000000;
            out_valid           <= 1'b0;
            out_predicted_taken <= 1'b0;
        end else if (stall) begin
            // hold: no assignment, registers keep their value
            out_pc              <= out_pc;
            out_instr           <= out_instr;
            out_valid           <= out_valid;
            out_predicted_taken <= out_predicted_taken;
        end else begin
            out_pc              <= in_pc;
            out_instr           <= in_instr;
            out_valid           <= in_valid;
            out_predicted_taken <= in_predicted_taken;
        end
    end

endmodule
