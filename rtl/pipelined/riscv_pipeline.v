//==========================================================================
// riscv_pipeline.v - 5-stage pipelined RV32I subset core
//
// Owner: integration (Member C merges; every member owns their stage)
//
//   IF          ID           EX          MEM         WB
//  +-----+    +------+    +--------+   +------+   +-------+
//  |pc_if|-->|decode |-->| ex_stage|-->| mem  |-->|  wb   |
//  +-----+ ^ +------+ ^  +--------+ ^ +------+ ^ +-------+
//       IF/ID      ID/EX        EX/MEM      MEM/WB
//
// Supported instructions: add sub addi lw sw beq bne
//
// Two parameters select the configuration.  Every variant is built from
// identical RTL, so each comparison isolates one feature:
//
//   FORWARD_EN  1 - full forwarding network, stalls only on load-use
//               0 - no forwarding, stall until the producer reaches WB
//
//   PREDICTOR   1 - 2-bit branch history table, predict at fetch
//               0 - static not-taken
//
// The three reported configurations are (0,0) "stall", (1,0) "fwd" and
// (1,1) "pred", against the single-cycle core as the reference.
//
// Hazard and control-flow summary:
//   RAW on an ALU result     -> forwarded, 0 cycle penalty (FORWARD_EN=1)
//   RAW load-use             -> 1 bubble
//   RAW any (FORWARD_EN=0)   -> up to 2 bubbles
//   Mispredicted branch      -> 2 flushed slots (resolved in EX)
//   Correctly predicted      -> 0 cycles, either direction
//   WAW / WAR                -> impossible: in-order issue, single write
//                               port, one architectural write per
//                               instruction, all writes in WB
//   Structural               -> none: separate instruction and data
//                               memories, register file has 2 read ports
//                               and 1 write port
//==========================================================================
`include "defines.vh"

module riscv_pipeline #(
    parameter IMEM_HEX   = "",
    parameter DMEM_HEX   = "",
    parameter FORWARD_EN = 1,
    parameter PREDICTOR  = 0,
    parameter BHT_INDEX_BITS = 6
) (
    input  wire                  clk,
    input  wire                  rst,

    // ---- observation ports for the testbench / performance counters ----
    output wire [`XLEN-1:0]      if_pc,
    output wire [31:0]           wb_instr,
    output wire                  retire_valid,   // an instruction left WB
    output wire                  stall_cycle,    // hazard stall this cycle
    output wire                  flush_event,    // MISPREDICT this cycle
    output wire                  branch_event,   // a branch resolved in EX
    output wire                  branch_taken,   // and it was taken
    output wire                  halted          // program done, pipe empty
);

    //======================================================================
    // Stage 1: IF
    //======================================================================
    wire [`XLEN-1:0] if_pc_w;
    wire [31:0]      if_instr;
    wire             if_valid, halt_fetch;

    wire             stall_pc, stall_if_id, bubble_id_ex;
    wire [`XLEN-1:0] ex_redirect_target;
    wire             ex_redirect;
    wire             if_is_branch, if_predicted_taken, predict_taken_raw;

    pc_if #(.IMEM_HEX(IMEM_HEX), .PREDICTOR(PREDICTOR)) u_if (
        .clk               (clk),
        .rst               (rst),
        .stall             (stall_pc),
        .redirect          (ex_redirect),
        .redirect_target   (ex_redirect_target),
        .predict_taken_raw (predict_taken_raw),
        .pc                (if_pc_w),
        .instr             (if_instr),
        .if_valid          (if_valid),
        .halt_fetch        (halt_fetch),
        .if_is_branch      (if_is_branch),
        .predicted_taken   (if_predicted_taken)
    );

    //======================================================================
    // IF/ID
    //======================================================================
    wire [`XLEN-1:0] id_pc;
    wire [31:0]      id_instr;
    wire             id_valid;

    wire             id_predicted_taken;

    if_id u_if_id (
        .clk                 (clk),
        .rst                 (rst),
        .stall               (stall_if_id),
        .flush               (ex_redirect),
        .in_pc               (if_pc_w),
        .in_instr            (if_instr),
        .in_valid            (if_valid),
        .in_predicted_taken  (if_predicted_taken),
        .out_pc              (id_pc),
        .out_instr           (id_instr),
        .out_valid           (id_valid),
        .out_predicted_taken (id_predicted_taken)
    );

    //======================================================================
    // Stage 2: ID
    //======================================================================
    wire [`XLEN-1:0] id_rs1_data, id_rs2_data, id_imm;
    wire [4:0]       id_rs1_addr, id_rs2_addr, id_rd_addr;
    wire             id_reg_write, id_alu_src, id_mem_read, id_mem_write;
    wire             id_mem_to_reg, id_branch, id_branch_ne;
    wire             id_uses_rs1, id_uses_rs2, id_illegal;
    wire [1:0]       id_alu_ctrl;

    wire             wb_we;
    wire [4:0]       wb_rd_addr;
    wire [`XLEN-1:0] wb_data;

    decode_stage u_id (
        .clk        (clk),
        .rst        (rst),
        .instr      (id_instr),
        .wb_we      (wb_we),
        .wb_rd_addr (wb_rd_addr),
        .wb_data    (wb_data),
        .rs1_data   (id_rs1_data),
        .rs2_data   (id_rs2_data),
        .imm        (id_imm),
        .rs1_addr   (id_rs1_addr),
        .rs2_addr   (id_rs2_addr),
        .rd_addr    (id_rd_addr),
        .reg_write  (id_reg_write),
        .alu_src    (id_alu_src),
        .alu_ctrl   (id_alu_ctrl),
        .mem_read   (id_mem_read),
        .mem_write  (id_mem_write),
        .mem_to_reg (id_mem_to_reg),
        .branch     (id_branch),
        .branch_ne  (id_branch_ne),
        .uses_rs1   (id_uses_rs1),
        .uses_rs2   (id_uses_rs2),
        .illegal    (id_illegal)
    );

    //======================================================================
    // ID/EX
    //======================================================================
    wire [`XLEN-1:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0]       ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [31:0]      ex_instr;
    wire             ex_valid;
    wire             ex_reg_write, ex_alu_src, ex_mem_read, ex_mem_write;
    wire             ex_mem_to_reg, ex_branch, ex_branch_ne;
    wire             ex_predicted_taken;
    wire [1:0]       ex_alu_ctrl;

    id_ex u_id_ex (
        .clk            (clk),
        .rst            (rst),
        .bubble         (bubble_id_ex | ex_redirect),
        .in_pc          (id_pc),
        .in_rs1_data    (id_rs1_data),
        .in_rs2_data    (id_rs2_data),
        .in_imm         (id_imm),
        .in_rs1_addr    (id_rs1_addr),
        .in_rs2_addr    (id_rs2_addr),
        .in_rd_addr     (id_rd_addr),
        .in_instr       (id_instr),
        .in_valid       (id_valid),
        .in_predicted_taken (id_predicted_taken),
        .in_reg_write   (id_reg_write),
        .in_alu_src     (id_alu_src),
        .in_alu_ctrl    (id_alu_ctrl),
        .in_mem_read    (id_mem_read),
        .in_mem_write   (id_mem_write),
        .in_mem_to_reg  (id_mem_to_reg),
        .in_branch      (id_branch),
        .in_branch_ne   (id_branch_ne),
        .out_pc         (ex_pc),
        .out_rs1_data   (ex_rs1_data),
        .out_rs2_data   (ex_rs2_data),
        .out_imm        (ex_imm),
        .out_rs1_addr   (ex_rs1_addr),
        .out_rs2_addr   (ex_rs2_addr),
        .out_rd_addr    (ex_rd_addr),
        .out_instr      (ex_instr),
        .out_valid      (ex_valid),
        .out_predicted_taken (ex_predicted_taken),
        .out_reg_write  (ex_reg_write),
        .out_alu_src    (ex_alu_src),
        .out_alu_ctrl   (ex_alu_ctrl),
        .out_mem_read   (ex_mem_read),
        .out_mem_write  (ex_mem_write),
        .out_mem_to_reg (ex_mem_to_reg),
        .out_branch     (ex_branch),
        .out_branch_ne  (ex_branch_ne)
    );

    //======================================================================
    // Branch predictor
    //
    // Placed after the ID/EX register because its update port reads
    // ex_pc, which is declared there.  Verilog creates an implicit 1-bit
    // net for an identifier used before its declaration, so connecting
    // ex_pc above this point silently truncated the update address to one
    // bit: every branch trained entry 0 and the table never learned
    // anything.  Prediction accuracy came out at exactly the static
    // not-taken rate, which is what made it visible.  The build scripts
    // now pass -Wall so iverilog reports the width mismatch.
    //
    // Instantiated inside a generate block so that the 2 x 64 counter
    // flip-flops exist ONLY in the PREDICTOR = 1 build.  Leaving the
    // instance in unconditionally and relying on the synthesiser to strip
    // it would make the area comparison between configurations
    // unreliable; this way each number reflects exactly the hardware that
    // configuration needs.
    //======================================================================
    generate
    if (PREDICTOR != 0) begin : g_predictor
        branch_predictor #(.INDEX_BITS(BHT_INDEX_BITS)) u_bp (
            .clk           (clk),
            .rst           (rst),
            .if_pc         (if_pc_w),
            .predict_taken (predict_taken_raw),
            .update_en     (branch_event),
            .update_pc     (ex_pc),
            .update_taken  (branch_taken)
        );
    end else begin : g_no_predictor
        assign predict_taken_raw = 1'b0;
    end
    endgenerate

    assign if_pc = if_pc_w;

    //======================================================================
    // Stage 3: EX
    //======================================================================
    wire [`XLEN-1:0] mem_alu_result, mem_store_data;
    wire [4:0]       mem_rd_addr;
    wire [31:0]      mem_instr;
    wire             mem_valid, mem_reg_write, mem_mem_read;
    wire             mem_mem_write, mem_mem_to_reg;

    wire             wb_valid, wb_reg_write, wb_mem_to_reg;
    wire [4:0]       wb_rd_addr_r;

    wire [1:0]       fwd_a, fwd_b;

    forwarding_unit #(.FORWARD_EN(FORWARD_EN)) u_fwd (
        .ex_rs1_addr   (ex_rs1_addr),
        .ex_rs2_addr   (ex_rs2_addr),
        .mem_valid     (mem_valid),
        .mem_reg_write (mem_reg_write),
        .mem_rd_addr   (mem_rd_addr),
        .wb_valid      (wb_valid),
        .wb_reg_write  (wb_reg_write),
        .wb_rd_addr    (wb_rd_addr_r),
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b)
    );

    wire [`XLEN-1:0] ex_alu_result, ex_store_data;

    ex_stage u_ex (
        .pc              (ex_pc),
        .rs1_data        (ex_rs1_data),
        .rs2_data        (ex_rs2_data),
        .imm             (ex_imm),
        .valid           (ex_valid),
        .predicted_taken (ex_predicted_taken),
        .alu_src         (ex_alu_src),
        .alu_ctrl        (ex_alu_ctrl),
        .branch          (ex_branch),
        .branch_ne       (ex_branch_ne),
        .fwd_a           (fwd_a),
        .fwd_b           (fwd_b),
        .fwd_mem_data    (mem_alu_result),
        .fwd_wb_data     (wb_data),
        .alu_result      (ex_alu_result),
        .store_data      (ex_store_data),
        .redirect        (ex_redirect),
        .redirect_target (ex_redirect_target),
        .branch_resolved (branch_event),
        .actual_taken    (branch_taken)
    );

    //======================================================================
    // EX/MEM
    //======================================================================
    ex_mem u_ex_mem (
        .clk            (clk),
        .rst            (rst),
        .bubble         (1'b0),
        .in_alu_result  (ex_alu_result),
        .in_store_data  (ex_store_data),
        .in_rd_addr     (ex_rd_addr),
        .in_instr       (ex_instr),
        .in_valid       (ex_valid),
        .in_reg_write   (ex_reg_write),
        .in_mem_read    (ex_mem_read),
        .in_mem_write   (ex_mem_write),
        .in_mem_to_reg  (ex_mem_to_reg),
        .out_alu_result (mem_alu_result),
        .out_store_data (mem_store_data),
        .out_rd_addr    (mem_rd_addr),
        .out_instr      (mem_instr),
        .out_valid      (mem_valid),
        .out_reg_write  (mem_reg_write),
        .out_mem_read   (mem_mem_read),
        .out_mem_write  (mem_mem_write),
        .out_mem_to_reg (mem_mem_to_reg)
    );

    //======================================================================
    // Stage 4: MEM
    //======================================================================
    wire [`XLEN-1:0] mem_rdata;

    mem_stage #(.DMEM_HEX(DMEM_HEX)) u_mem (
        .clk        (clk),
        .valid      (mem_valid),
        .addr       (mem_alu_result),
        .mem_read   (mem_mem_read),
        .mem_write  (mem_mem_write),
        .store_data (mem_store_data),
        .mem_data   (mem_rdata)
    );

    //======================================================================
    // MEM/WB
    //======================================================================
    wire [`XLEN-1:0] wb_alu_result, wb_mem_data;
    wire [31:0]      wb_instr_r;

    mem_wb u_mem_wb (
        .clk            (clk),
        .rst            (rst),
        .bubble         (1'b0),
        .in_alu_result  (mem_alu_result),
        .in_mem_data    (mem_rdata),
        .in_rd_addr     (mem_rd_addr),
        .in_instr       (mem_instr),
        .in_valid       (mem_valid),
        .in_reg_write   (mem_reg_write),
        .in_mem_to_reg  (mem_mem_to_reg),
        .out_alu_result (wb_alu_result),
        .out_mem_data   (wb_mem_data),
        .out_rd_addr    (wb_rd_addr_r),
        .out_instr      (wb_instr_r),
        .out_valid      (wb_valid),
        .out_reg_write  (wb_reg_write),
        .out_mem_to_reg (wb_mem_to_reg)
    );

    //======================================================================
    // Stage 5: WB
    //======================================================================
    wb_stage u_wb (
        .valid      (wb_valid),
        .reg_write  (wb_reg_write),
        .mem_to_reg (wb_mem_to_reg),
        .alu_result (wb_alu_result),
        .mem_data   (wb_mem_data),
        .rd_addr_in (wb_rd_addr_r),
        .wb_data    (wb_data),
        .wb_we      (wb_we),
        .wb_rd_addr (wb_rd_addr)
    );

    //======================================================================
    // Hazard detection
    //======================================================================
    hazard_unit #(.FORWARD_EN(FORWARD_EN)) u_hazard (
        .id_valid      (id_valid),
        .id_rs1_addr   (id_rs1_addr),
        .id_rs2_addr   (id_rs2_addr),
        .id_uses_rs1   (id_uses_rs1),
        .id_uses_rs2   (id_uses_rs2),
        .ex_valid      (ex_valid),
        .ex_rd_addr    (ex_rd_addr),
        .ex_reg_write  (ex_reg_write),
        .ex_mem_read   (ex_mem_read),
        .mem_valid     (mem_valid),
        .mem_rd_addr   (mem_rd_addr),
        .mem_reg_write (mem_reg_write),
        .stall_pc      (stall_pc),
        .stall_if_id   (stall_if_id),
        .bubble_id_ex  (bubble_id_ex)
    );

    //======================================================================
    // Observation / performance signals
    //======================================================================
    assign wb_instr     = wb_instr_r;
    assign retire_valid = wb_valid;
    assign stall_cycle  = stall_pc;
    // A flush is caused by a MISPREDICT, not by a taken branch.  With
    // PREDICTOR = 0 the two coincide, because a static not-taken policy
    // mispredicts exactly the taken branches; with PREDICTOR = 1 they
    // diverge, and the difference is the whole benefit of the feature.
    assign flush_event  = ex_redirect;

    // The program is finished when IF has reached the halt word AND every
    // stage is empty, i.e. the pipeline has fully drained.
    assign halted = halt_fetch & ~id_valid & ~ex_valid & ~mem_valid & ~wb_valid;

endmodule
