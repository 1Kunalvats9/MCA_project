//==========================================================================
// tb_hazards.v - Directed self-checking hazard test
//
// Owner: Member D (hazard logic) with Member E (harness)
//
// Runs programs/hazard_suite.s and checks every architectural register
// and the relevant data memory words against hardcoded expected values.
// Compiled once per configuration:
//
//   -DCORE_SINGLE        single-cycle reference
//   -DCORE_PIPE -DFWD=0  pipelined, stall only
//   -DCORE_PIPE -DFWD=1  pipelined, forwarding
//
// All three must pass with identical expected values.  That is the point:
// the expected values are architectural, so they do not depend on how
// many bubbles the implementation needs.
//==========================================================================
`timescale 1ns/1ps
`include "defines.vh"

`ifndef FWD
  `define FWD 1
`endif
`ifndef PRED
  `define PRED 0
`endif
`ifndef TIMEOUT
  `define TIMEOUT 200000
`endif

module tb_hazards;

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire [31:0] pc_obs, instr_obs;
    wire        retire_valid, halted, stall_cycle, flush_event;
    wire        branch_event, branch_taken;

`ifdef CORE_SINGLE
    riscv_single_cycle dut (
        .clk(clk), .rst(rst), .pc_out(pc_obs), .instr_out(instr_obs),
        .retire_valid(retire_valid), .halted(halted)
    );
    assign stall_cycle  = 1'b0;
    assign flush_event  = 1'b0;
    assign branch_event = 1'b0;
    assign branch_taken = 1'b0;
    `define IMEM_ARRAY dut.u_imem.mem
    `define DMEM_ARRAY dut.u_dmem.mem
    `define REGS_ARRAY dut.u_regfile.regs
`else
    riscv_pipeline #(.FORWARD_EN(`FWD), .PREDICTOR(`PRED)) dut (
        .clk(clk), .rst(rst), .if_pc(pc_obs), .wb_instr(instr_obs),
        .retire_valid(retire_valid), .stall_cycle(stall_cycle),
        .flush_event(flush_event), .branch_event(branch_event),
        .branch_taken(branch_taken), .halted(halted)
    );
    `define IMEM_ARRAY dut.u_if.u_imem.mem
    `define DMEM_ARRAY dut.u_mem.u_dmem.mem
    `define REGS_ARRAY dut.u_id.u_regfile.regs
`endif

    integer errors = 0;
    integer checks = 0;
    integer cycles = 0;
    integer instrs = 0;
    integer i;
    //----------------------------------------------------------------------
    // Quiet hex loader.
    //
    // $readmemh warns ("Not enough words in the file") whenever the image
    // is shorter than the memory array, which it almost always is.  The
    // warning is harmless but it buries the real output, so the images are
    // read word by word instead and loading simply stops at end of file.
    //----------------------------------------------------------------------
    integer lf;
    integer rc;
    integer nwords;
    reg [31:0] wtmp;

    reg [8*256-1:0] imem_path, cfg_name, vcd_path;

    always @(posedge clk) begin
        if (!rst && !halted) begin
            cycles <= cycles + 1;
            if (retire_valid) instrs <= instrs + 1;
        end
    end

    //----------------------------------------------------------------------
    task check_reg (input integer idx, input [31:0] exp,
                    input [8*48-1:0] why);
        begin
            checks = checks + 1;
            if (`REGS_ARRAY[idx] !== exp) begin
                $display("  FAIL x%0d = %0d (0x%08x), expected %0d  <- %0s",
                         idx, $signed(`REGS_ARRAY[idx]), `REGS_ARRAY[idx],
                         $signed(exp), why);
                errors = errors + 1;
            end
        end
    endtask

    task check_mem (input integer idx, input [31:0] exp,
                    input [8*48-1:0] why);
        begin
            checks = checks + 1;
            if (`DMEM_ARRAY[idx] !== exp) begin
                $display("  FAIL dmem[%0d] = %0d, expected %0d  <- %0s",
                         idx, $signed(`DMEM_ARRAY[idx]), $signed(exp), why);
                errors = errors + 1;
            end
        end
    endtask

    //----------------------------------------------------------------------
    initial begin
        if (!$value$plusargs("imem=%s", imem_path))
            imem_path = "programs/hazard_suite.imem.hex";
        if (!$value$plusargs("cfg=%s", cfg_name))
            cfg_name = "cfg";

        for (i = 0; i < `MEM_WORDS; i = i + 1) begin
            `IMEM_ARRAY[i] = 32'h00000000;
            `DMEM_ARRAY[i] = 32'h00000000;
        end
        nwords = 0;
        lf = $fopen(imem_path, "r");
        if (lf == 0) begin
            $display("ERROR: cannot open %0s", imem_path);
            $finish;
        end
        rc = $fscanf(lf, "%h\n", wtmp);
        while (rc == 1 && nwords < `MEM_WORDS) begin
            `IMEM_ARRAY[nwords] = wtmp;
            nwords = nwords + 1;
            rc = $fscanf(lf, "%h\n", wtmp);
        end
        $fclose(lf);

        if ($value$plusargs("vcdfile=%s", vcd_path)) begin
            $dumpfile(vcd_path);
            $dumpvars(0, tb_hazards);
        end else if ($test$plusargs("vcd")) begin
            $dumpfile("results/hazard_suite.vcd");
            $dumpvars(0, tb_hazards);
        end

        // Reset deasserted on a negedge to avoid racing the counter
        // always-block at the posedge.  See the note in tb/tb_core.v.
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        wait (halted === 1'b1);
        @(posedge clk);

        $display("");
        $display("== tb_hazards / %0s ==  (%0d instructions in %0d cycles)",
                 cfg_name, instrs, cycles);

        // group 1 - basic RAW, distance 1 and 2
        check_reg(1,  32'd10,  "addi");
        check_reg(2,  32'd3,   "addi");
        check_reg(3,  32'd13,  "EX/MEM->EX forward (dist 1+2)");
        check_reg(4,  32'd7,   "sub with forwarded operands");
        check_reg(5,  32'd20,  "chained forward");

        // group 2 - distance 2 only
        check_reg(6,  32'd100, "addi");
        check_reg(7,  32'd1,   "independent filler");
        check_reg(8,  32'd200, "MEM/WB->EX forward (dist 2)");

        // group 3 - forwarding priority
        check_reg(9,  32'd2,   "second write wins");
        check_reg(10, 32'd2,   "forward priority: EX/MEM over MEM/WB");

        // group 4 - x0 handling
        check_reg(0,  32'd0,   "writes to x0 discarded");
        check_reg(12, 32'd10,  "no forwarding from rd == x0");

        // group 5 - load-use
        check_reg(13, 32'd64,  "base address");
        check_reg(14, 32'd20,  "store value");
        check_reg(15, 32'd20,  "lw after sw");
        check_reg(16, 32'd40,  "load-use stall + MEM/WB forward");
        check_mem(16, 32'd20,  "sw committed");

        // group 6 - store data forwarding
        check_reg(17, 32'd20,  "add before sw");
        check_reg(18, 32'd20,  "store data was forwarded");
        check_mem(17, 32'd20,  "forwarded store data in memory");

        // group 7 - branch not taken
        check_reg(19, 32'd5,   "addi");
        check_reg(20, 32'd5,   "addi");
        check_reg(21, 32'd1,   "fall-through after not-taken branch");

        // group 8 - branch taken, two slots flushed
        check_reg(22, 32'd0,   "flushed slot 1 must not commit");
        check_reg(23, 32'd0,   "flushed slot 2 must not commit");
        check_reg(24, 32'd7,   "branch target executed");

        // group 9 - operand forwarded into the comparator
        check_reg(25, 32'd4,   "addi");
        check_reg(26, 32'd4,   "add");
        check_reg(27, 32'd0,   "flushed after forwarded-operand branch");
        check_reg(28, 32'd1,   "branch target executed");

        // group 10 - a flushed store must not reach memory
        check_reg(29, 32'd123, "addi");
        check_reg(30, 32'd0,   "flushed slot must not commit");
        check_mem(20, 32'd0,   "FLUSHED STORE MUST NOT WRITE MEMORY");
        check_reg(31, 32'd42,  "branch target executed");

        if (errors == 0)
            $display("== tb_hazards %0s PASSED (%0d checks) ==", cfg_name, checks);
        else
            $display("== tb_hazards %0s FAILED: %0d of %0d checks ==",
                     cfg_name, errors, checks);
        $finish;
    end

    initial begin
        #(`TIMEOUT);
        $display("ERROR: tb_hazards/%0s TIMED OUT (cycles=%0d)", cfg_name, cycles);
        $finish;
    end

endmodule
