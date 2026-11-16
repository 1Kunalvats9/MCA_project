//==========================================================================
// ex_stage.v - Stage 3: execute
//
// Owner: Member C (Execute)
//
// Contains the two forwarding multiplexers, the ALU, the branch
// comparator and the branch target adder.
//
// Operand flow:
//
//   rs1_data --\
//   mem_fwd  ---> [fwd_a mux] --> a_fwd --> ALU a, comparator a
//   wb_fwd   --/
//
//   rs2_data --\
//   mem_fwd  ---> [fwd_b mux] --> b_fwd --> [alu_src mux] --> ALU b
//   wb_fwd   --/                        \-> store_data (to EX/MEM)
//
// The forwarding muxes sit BEFORE the alu_src mux, so a forwarded value
// reaches both the ALU and the store-data path.  Putting the forwarding
// mux after alu_src would leave stores reading a stale register value,
// which is the bug the store-forward test in tb_hazards.v checks for.
//
// Branch resolution happens here, in parallel with the ALU, using the
// forwarded operands.  Everything it drives is gated with valid, so a
// bubble or an already-flushed instruction can never redirect the PC or
// train the predictor.
//
//--------------------------------------------------------------------------
// Checking the prediction
//--------------------------------------------------------------------------
// This stage is where a prediction made in IF is confirmed or overturned.
//
//   actual_taken = branch AND the condition holds
//   mispredict   = valid AND (actual_taken XOR predicted_taken)
//
// The XOR covers both directions, which is the whole point of moving from
// static to dynamic prediction:
//
//   predicted  actual   outcome
//   ---------  ------   ----------------------------------------------
//       0        0      correct, nothing happens (not-taken branch, or
//                       any non-branch instruction)
//       0        1      mispredicted not-taken -> redirect to pc + imm
//       1        0      mispredicted taken     -> redirect to pc + 4
//       1        1      correct, NO flush: the target was already fetched
//
// The third row is new.  Static not-taken can only ever be wrong in one
// direction, so it only ever needs the branch target.  A predictor that
// can say "taken" can also be wrong about that, and then the machine has
// to recover to the fall-through path - so redirect_target is a mux, not
// just the branch target adder.
//
// The fourth row is where the performance comes from: a correctly
// predicted taken branch costs nothing at all, because IF already
// fetched from the target two cycles ago.
//
// Non-branch instructions have predicted_taken tied low in IF, so
// actual_taken and predicted_taken are both 0 and mispredict is 0.
//==========================================================================
`include "defines.vh"

module ex_stage (
    input  wire [`XLEN-1:0]      pc,
    input  wire [`XLEN-1:0]      rs1_data,
    input  wire [`XLEN-1:0]      rs2_data,
    input  wire [`XLEN-1:0]      imm,
    input  wire                  valid,
    input  wire                  predicted_taken,

    // control
    input  wire                  alu_src,
    input  wire [1:0]            alu_ctrl,
    input  wire                  branch,
    input  wire                  branch_ne,

    // forwarding
    input  wire [1:0]            fwd_a,
    input  wire [1:0]            fwd_b,
    input  wire [`XLEN-1:0]      fwd_mem_data,   // from EX/MEM
    input  wire [`XLEN-1:0]      fwd_wb_data,    // from MEM/WB (post WB mux)

    output wire [`XLEN-1:0]      alu_result,
    output wire [`XLEN-1:0]      store_data,

    // control-flow correction, driven to the IF stage
    output wire                  redirect,
    output wire [`XLEN-1:0]      redirect_target,

    // predictor training and statistics
    output wire                  branch_resolved,
    output wire                  actual_taken
);

    //---------------------------------------------------------- forwarding
    reg [`XLEN-1:0] a_fwd, b_fwd;

    always @(*) begin
        case (fwd_a)
            `FWD_MEM: a_fwd = fwd_mem_data;
            `FWD_WB:  a_fwd = fwd_wb_data;
            default:  a_fwd = rs1_data;
        endcase
        case (fwd_b)
            `FWD_MEM: b_fwd = fwd_mem_data;
            `FWD_WB:  b_fwd = fwd_wb_data;
            default:  b_fwd = rs2_data;
        endcase
    end

    assign store_data = b_fwd;

    //----------------------------------------------------------------- ALU
    wire [`XLEN-1:0] alu_b = alu_src ? imm : b_fwd;
    wire             alu_zero;

    alu u_alu (
        .alu_ctrl (alu_ctrl),
        .a        (a_fwd),
        .b        (alu_b),
        .result   (alu_result),
        .zero     (alu_zero)
    );

    //-------------------------------------------------------------- branch
    wire cond_met;

    branch_cmp u_bcmp (
        .branch      (branch),
        .branch_ne   (branch_ne),
        .rs1_data    (a_fwd),
        .rs2_data    (b_fwd),
        .take_branch (cond_met)
    );

    wire [`XLEN-1:0] branch_target = pc + imm;      // taken path
    wire [`XLEN-1:0] fallthrough   = pc + 32'd4;    // not-taken path

    assign actual_taken    = cond_met;              // cond_met already
                                                    // includes `branch`
    assign branch_resolved = branch & valid;

    assign redirect        = valid & (actual_taken ^ predicted_taken);
    assign redirect_target = actual_taken ? branch_target : fallthrough;

endmodule
