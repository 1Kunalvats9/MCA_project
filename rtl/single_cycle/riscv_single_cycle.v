//==========================================================================
// riscv_single_cycle.v - Single-cycle RV32I subset core
//
// Owner: whole team (built first, in week 1, as the correctness reference)
//
// Supported instructions: add sub addi lw sw beq bne
//
// Every instruction completes in exactly one clock cycle, so CPI = 1.00 by
// construction.  That makes this core useless as a fast design (the clock
// period must cover IF + ID + EX + MEM + WB in series) but extremely
// useful as a golden model: the pipelined cores must produce the same
// final register file and data memory for every benchmark.
//
// Halt convention: fetching the word 0x00000000 freezes the PC and
// deasserts retire_valid.  See rtl/common/imem.v.
//==========================================================================
`include "defines.vh"

module riscv_single_cycle #(
    parameter IMEM_HEX = "",
    parameter DMEM_HEX = ""
) (
    input  wire                  clk,
    input  wire                  rst,

    // Observation ports for the testbench / performance counters.
    output wire [`XLEN-1:0]      pc_out,
    output wire [31:0]           instr_out,
    output wire                  retire_valid,
    output wire                  halted
);

    //----------------------------------------------------------------------
    // Program counter
    //----------------------------------------------------------------------
    reg  [`XLEN-1:0] pc;
    wire [`XLEN-1:0] pc_plus4 = pc + 32'd4;
    wire [`XLEN-1:0] pc_next;

    always @(posedge clk) begin
        if (rst)
            pc <= {`XLEN{1'b0}};
        else if (!halted)
            pc <= pc_next;
    end

    assign pc_out = pc;

    //----------------------------------------------------------------------
    // Instruction fetch
    //----------------------------------------------------------------------
    wire [31:0] instr;

    imem #(.HEXFILE(IMEM_HEX)) u_imem (
        .addr  (pc),
        .instr (instr)
    );

    assign instr_out    = instr;
    assign halted       = (instr == 32'h00000000);
    assign retire_valid = ~halted & ~rst;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rs1_a  = instr[19:15];
    wire [4:0] rs2_a  = instr[24:20];
    wire [4:0] rd_a   = instr[11:7];

    //----------------------------------------------------------------------
    // Control
    //----------------------------------------------------------------------
    wire       reg_write, alu_src, mem_read, mem_write, mem_to_reg;
    wire       branch, branch_ne, illegal;
    wire [1:0] alu_ctrl;

    control_unit u_ctrl (
        .opcode     (opcode),
        .funct3     (funct3),
        .funct7     (funct7),
        .reg_write  (reg_write),
        .alu_src    (alu_src),
        .alu_ctrl   (alu_ctrl),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .mem_to_reg (mem_to_reg),
        .branch     (branch),
        .branch_ne  (branch_ne),
        .illegal    (illegal)
    );

    //----------------------------------------------------------------------
    // Register file and immediate
    //----------------------------------------------------------------------
    wire [`XLEN-1:0] rs1_data, rs2_data, imm, wb_data;

    // WB_BYPASS(0): the single-cycle core reads and writes the register
    // file in the same cycle for the SAME instruction, so the bypass
    // would close a combinational loop.  See rtl/common/regfile.v.
    regfile #(.WB_BYPASS(0)) u_regfile (
        .clk      (clk),
        .rst      (rst),
        .rs1_addr (rs1_a),
        .rs2_addr (rs2_a),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .we       (reg_write & ~halted),
        .rd_addr  (rd_a),
        .rd_data  (wb_data)
    );

    imm_gen u_imm (
        .instr (instr),
        .imm   (imm)
    );

    //----------------------------------------------------------------------
    // Execute
    //----------------------------------------------------------------------
    wire [`XLEN-1:0] alu_b = alu_src ? imm : rs2_data;
    wire [`XLEN-1:0] alu_result;
    wire             alu_zero, take_branch;

    alu u_alu (
        .alu_ctrl (alu_ctrl),
        .a        (rs1_data),
        .b        (alu_b),
        .result   (alu_result),
        .zero     (alu_zero)
    );

    branch_cmp u_bcmp (
        .branch      (branch),
        .branch_ne   (branch_ne),
        .rs1_data    (rs1_data),
        .rs2_data    (rs2_data),
        .take_branch (take_branch)
    );

    assign pc_next = take_branch ? (pc + imm) : pc_plus4;

    //----------------------------------------------------------------------
    // Memory
    //----------------------------------------------------------------------
    wire [`XLEN-1:0] mem_rdata;

    dmem #(.HEXFILE(DMEM_HEX)) u_dmem (
        .clk   (clk),
        .addr  (alu_result),
        .we    (mem_write & ~halted),
        .re    (mem_read),
        .wdata (rs2_data),
        .rdata (mem_rdata)
    );

    //----------------------------------------------------------------------
    // Write back
    //----------------------------------------------------------------------
    assign wb_data = (mem_to_reg == `WB_MEM) ? mem_rdata : alu_result;

endmodule
