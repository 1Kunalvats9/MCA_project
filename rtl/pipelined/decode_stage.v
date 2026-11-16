//==========================================================================
// decode_stage.v - Stage 2: instruction decode and register read
//
// Owner: Member B (Decode)
//
// Wraps the register file, the immediate generator and the main control
// decoder.  The register file lives here even though its write port is
// driven from the WB stage: there is exactly one physical register file,
// read in ID and written in WB, and its internal write-to-read bypass is
// what removes the WB->ID hazard.
//==========================================================================
`include "defines.vh"

module decode_stage (
    input  wire                  clk,
    input  wire                  rst,

    input  wire [31:0]           instr,

    // write port, driven by the WB stage
    input  wire                  wb_we,
    input  wire [4:0]            wb_rd_addr,
    input  wire [`XLEN-1:0]      wb_data,

    // register read results
    output wire [`XLEN-1:0]      rs1_data,
    output wire [`XLEN-1:0]      rs2_data,
    output wire [`XLEN-1:0]      imm,
    output wire [4:0]            rs1_addr,
    output wire [4:0]            rs2_addr,
    output wire [4:0]            rd_addr,

    // control bundle
    output wire                  reg_write,
    output wire                  alu_src,
    output wire [1:0]            alu_ctrl,
    output wire                  mem_read,
    output wire                  mem_write,
    output wire                  mem_to_reg,
    output wire                  branch,
    output wire                  branch_ne,
    output wire                  uses_rs1,
    output wire                  uses_rs2,
    output wire                  illegal
);

    assign rs1_addr = instr[19:15];
    assign rs2_addr = instr[24:20];
    assign rd_addr  = instr[11:7];

    control_unit u_ctrl (
        .opcode     (instr[6:0]),
        .funct3     (instr[14:12]),
        .funct7     (instr[31:25]),
        .reg_write  (reg_write),
        .alu_src    (alu_src),
        .alu_ctrl   (alu_ctrl),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .branch     (branch),
        .branch_ne  (branch_ne),
        .uses_rs1   (uses_rs1),
        .uses_rs2   (uses_rs2),
        .illegal    (illegal)
    );

    imm_gen u_imm (
        .instr (instr),
        .imm   (imm)
    );

    // WB_BYPASS(1): the write comes from an older instruction in WB, so
    // the bypass removes the WB -> ID hazard.  See rtl/common/regfile.v.
    regfile #(.WB_BYPASS(1)) u_regfile (
        .clk      (clk),
        .rst      (rst),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .we       (wb_we),
        .rd_addr  (wb_rd_addr),
        .rd_data  (wb_data)
    );

endmodule
