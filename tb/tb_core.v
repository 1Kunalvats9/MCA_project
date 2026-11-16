//==========================================================================
// tb_core.v - Benchmark harness and performance counter testbench
//
// Owner: Member E (Verification / infrastructure)
//
// One testbench drives all three configurations.  Which core is
// instantiated is selected at compile time:
//
//   -DCORE_SINGLE                    single-cycle reference
//   -DCORE_PIPE -DFWD=0              pipelined, no forwarding
//   -DCORE_PIPE -DFWD=1              pipelined, full forwarding
//   -DCORE_PIPE -DFWD=1 -DPRED=1     pipelined, forwarding + 2-bit predictor
//
// The program is selected at RUN time with plusargs, so one compiled
// binary runs every benchmark:
//
//   vvp a.out +imem=programs/foo.imem.hex +dmem=programs/foo.dmem.hex \
//             +name=foo +cfg=fwd +csv=results/perf.csv +sig=results/foo.fwd.sig
//
// Outputs:
//   stdout : human readable cycle / CPI / IPC report
//   +csv   : one appended line, used to build the comparison table
//   +sig   : architectural signature (x1..x31 and dmem[0..31]).  The two
//            pipelined configurations must produce a signature byte-for-
//            byte identical to the single-cycle reference.  That is the
//            golden-model check, and it is what actually proves the
//            pipeline correct - counting cycles only proves it is fast.
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

module tb_core;

    reg clk = 0;
    reg rst = 1;

    always #5 clk = ~clk;          // 100 MHz nominal simulation clock

    //----------------------------------------------------------------------
    // Device under test
    //----------------------------------------------------------------------
    wire [31:0] pc_obs, instr_obs;
    wire        retire_valid, halted;
    wire        stall_cycle, flush_event, branch_event, branch_taken;

`ifdef CORE_SINGLE
    riscv_single_cycle dut (
        .clk          (clk),
        .rst          (rst),
        .pc_out       (pc_obs),
        .instr_out    (instr_obs),
        .retire_valid (retire_valid),
        .halted       (halted)
    );
    assign stall_cycle  = 1'b0;
    assign flush_event  = 1'b0;
    assign branch_event = 1'b0;
    assign branch_taken = 1'b0;
    `define CFG_NAME   "single"
    `define IMEM_ARRAY dut.u_imem.mem
    `define DMEM_ARRAY dut.u_dmem.mem
    `define REGS_ARRAY dut.u_regfile.regs
`else
    riscv_pipeline #(.FORWARD_EN(`FWD), .PREDICTOR(`PRED)) dut (
        .clk          (clk),
        .rst          (rst),
        .if_pc        (pc_obs),
        .wb_instr     (instr_obs),
        .retire_valid (retire_valid),
        .stall_cycle  (stall_cycle),
        .flush_event  (flush_event),
        .branch_event (branch_event),
        .branch_taken (branch_taken),
        .halted       (halted)
    );
    `define IMEM_ARRAY dut.u_if.u_imem.mem
    `define DMEM_ARRAY dut.u_mem.u_dmem.mem
    `define REGS_ARRAY dut.u_id.u_regfile.regs
`endif

    //----------------------------------------------------------------------
    // Performance counters
    //----------------------------------------------------------------------
    integer cycles         = 0;
    integer instrs         = 0;
    integer stall_cycles   = 0;
    integer branches       = 0;   // branches resolved in EX
    integer taken_branches = 0;   // of which, taken
    integer mispredicts    = 0;   // of which, predicted wrongly

    // Sampled at the rising edge, so each counter sees the value that was
    // held during the clock cycle now ending.  Counting stops as soon as
    // halted is asserted, i.e. the drain cycle itself is not charged.
    always @(posedge clk) begin
        if (!rst && !halted) begin
            cycles <= cycles + 1;
            if (retire_valid)                 instrs         <= instrs + 1;
            if (stall_cycle)                  stall_cycles   <= stall_cycles + 1;
            if (branch_event)                 branches       <= branches + 1;
            if (branch_event & branch_taken)  taken_branches <= taken_branches + 1;
            if (flush_event)                  mispredicts    <= mispredicts + 1;
        end
    end

    //----------------------------------------------------------------------
    // Run control
    //----------------------------------------------------------------------
    reg [8*256-1:0] imem_path, dmem_path, csv_path, sig_path;
    reg [8*256-1:0] prog_name, cfg_name, vcd_path;
    integer fd, i;
    real accuracy;
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

    real cpi, ipc;

    initial begin
        if (!$value$plusargs("imem=%s", imem_path)) begin
            $display("ERROR: no +imem=<file> given");
            $finish;
        end
        if (!$value$plusargs("name=%s", prog_name)) prog_name = "program";
        if (!$value$plusargs("cfg=%s",  cfg_name))  cfg_name  = "cfg";

        // Initialise both memories, then load the program image.
        for (i = 0; i < `MEM_WORDS; i = i + 1) begin
            `IMEM_ARRAY[i] = 32'h00000000;   // halt word
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
        $display("loaded %0d instruction words from %0s", nwords, imem_path);

        if ($value$plusargs("dmem=%s", dmem_path)) begin
            nwords = 0;
            lf = $fopen(dmem_path, "r");
            if (lf != 0) begin
                rc = $fscanf(lf, "%h\n", wtmp);
                while (rc == 1 && nwords < `MEM_WORDS) begin
                    `DMEM_ARRAY[nwords] = wtmp;
                    nwords = nwords + 1;
                    rc = $fscanf(lf, "%h\n", wtmp);
                end
                $fclose(lf);
                if (nwords > 0)
                    $display("loaded %0d data words from %0s", nwords, dmem_path);
            end
        end

        // The VCD path is passed in explicitly.  Building it by
        // concatenating the plusarg strings does not work: a string read
        // by $value$plusargs lands right-justified in a fixed-width reg,
        // so {"results/", prog_name, ".vcd"} embeds ~250 pad bytes.
        if ($value$plusargs("vcdfile=%s", vcd_path)) begin
            $dumpfile(vcd_path);
            $dumpvars(0, tb_core);
        end else if ($test$plusargs("vcd")) begin
            $dumpfile("results/dump.vcd");
            $dumpvars(0, tb_core);
        end

        // Reset for two cycles, then deassert on a NEGEDGE.
        //
        // Deasserting rst with a blocking assignment immediately after a
        // posedge creates a race: the counter and trace always-blocks
        // sample rst at that same edge, and whether they see 1 or 0
        // depends on procedural ordering within the time step.  That made
        // the cycle count non-deterministic by +/-1, which is enough to
        // corrupt every CPI figure.  Releasing reset mid-cycle removes
        // the race entirely.
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Run to completion.  The timeout lives in its own initial block
        // below (plain Verilog-2001, no fork/join_any) so that a hang is
        // reported instead of simulating forever.
        wait (halted === 1'b1);

        @(posedge clk);
        print_report;
        write_signature;
        append_csv;
        $finish;
    end

    //----------------------------------------------------------------------
    // Watchdog
    //----------------------------------------------------------------------
    initial begin
        #(`TIMEOUT);
        $display("ERROR: %0s/%0s TIMED OUT after %0d ns (cycles=%0d, instrs=%0d)",
                 prog_name, cfg_name, `TIMEOUT, cycles, instrs);
        print_report;
        $finish;
    end


    //----------------------------------------------------------------------
    // Pipeline occupancy trace  (+trace)
    //
    // Prints, for every clock cycle, which instruction occupies each of
    // the five stages.  This is the pipeline timing diagram asked for in
    // the deliverables, in text form: instruction overlap, bubbles from
    // stalls, and the two slots killed by a taken branch are all directly
    // visible without having to read a waveform.
    //
    // The trace reads the stage instruction words and valid bits
    // hierarchically out of the DUT, so it needs no extra RTL and costs
    // nothing in synthesis.
    //----------------------------------------------------------------------
`ifdef CORE_PIPE
    function [8*9-1:0] disasm (input [31:0] iw, input v);
        reg [6:0] op;
        reg [2:0] f3;
        reg [6:0] f7;
        begin
            op = iw[6:0];
            f3 = iw[14:12];
            f7 = iw[31:25];
            if (!v)                      disasm = "  --     ";
            else if (iw == 32'h00000013) disasm = "nop      ";
            else case (op)
                `OP_RTYPE:  disasm = (f7 == `F7_SUB) ? "sub      " : "add      ";
                `OP_IARITH: disasm = "addi     ";
                `OP_LOAD:   disasm = "lw       ";
                `OP_STORE:  disasm = "sw       ";
                `OP_BRANCH: disasm = (f3 == `F3_BNE) ? "bne      " : "beq      ";
                default:    disasm = "???      ";
            endcase
        end
    endfunction

    // The trace prints cycles+1 rather than keeping its own counter, so
    // the cycle numbers in the trace are the same numbers the CPI figures
    // are computed from, by construction.
    always @(posedge clk) begin
        if (!rst && !halted && $test$plusargs("trace")) begin
            if (cycles == 0) begin
                $display("");
                $display("Pipeline occupancy trace: %0s [%0s]",
                         prog_name, cfg_name);
                $display("cyc | IF pc | ID        | EX        | MEM       | WB        | event");
                $display("----+-------+-----------+-----------+-----------+-----------+--------------------");
            end
            $display("%3d | %5d | %0s | %0s | %0s | %0s | %0s%0s",
                     cycles + 1, dut.u_if.pc_reg,
                     disasm(dut.id_instr,    dut.id_valid),
                     disasm(dut.ex_instr,    dut.ex_valid),
                     disasm(dut.mem_instr,   dut.mem_valid),
                     disasm(dut.wb_instr_r,  dut.wb_valid),
                     stall_cycle ? "STALL (bubble into EX) " : "",
                     flush_event ? "MISPREDICT -> flush IF/ID and ID/EX" : "");
        end
    end
`endif

    //----------------------------------------------------------------------
    task print_report;
        begin
            cpi = (instrs == 0) ? 0.0 : (1.0 * cycles) / (1.0 * instrs);
            ipc = (cycles == 0) ? 0.0 : (1.0 * instrs) / (1.0 * cycles);
            $display("");
            $display("---- %0s / %0s ----", prog_name, cfg_name);
            $display("  instructions retired : %0d", instrs);
            $display("  clock cycles         : %0d", cycles);
            $display("  stall cycles         : %0d", stall_cycles);
            $display("  branches resolved    : %0d  (%0d taken)",
                     branches, taken_branches);
            $display("  mispredictions       : %0d  (%0d flushed slots)",
                     mispredicts, mispredicts * 2);
            accuracy = (branches == 0) ? 100.0 :
                       100.0 * (1.0 * (branches - mispredicts)) / (1.0 * branches);
            $display("  prediction accuracy  : %f %%", accuracy);
            $display("  CPI                  : %f", cpi);
            $display("  IPC                  : %f", ipc);
            $display("  final x1..x8         : %0d %0d %0d %0d %0d %0d %0d %0d",
                     `REGS_ARRAY[1], `REGS_ARRAY[2], `REGS_ARRAY[3],
                     `REGS_ARRAY[4], `REGS_ARRAY[5], `REGS_ARRAY[6],
                     `REGS_ARRAY[7], `REGS_ARRAY[8]);
        end
    endtask

    //----------------------------------------------------------------------
    // Architectural signature: everything software can observe.
    //----------------------------------------------------------------------
    task write_signature;
        begin
            if ($value$plusargs("sig=%s", sig_path)) begin
                fd = $fopen(sig_path, "w");
                if (fd == 0) begin
                    $display("ERROR: cannot open signature file");
                end else begin
                    for (i = 1; i < 32; i = i + 1)
                        $fdisplay(fd, "x%0d %08x", i, `REGS_ARRAY[i]);
                    for (i = 0; i < 32; i = i + 1)
                        $fdisplay(fd, "m%0d %08x", i, `DMEM_ARRAY[i]);
                    $fclose(fd);
                end
            end
        end
    endtask

    //----------------------------------------------------------------------
    task append_csv;
        begin
            if ($value$plusargs("csv=%s", csv_path)) begin
                fd = $fopen(csv_path, "a");
                if (fd != 0) begin
                    $fdisplay(fd, "%0s,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%f,%f",
                              prog_name, cfg_name, instrs, cycles,
                              stall_cycles, branches, taken_branches,
                              mispredicts, cpi, ipc);
                    $fclose(fd);
                end
            end
        end
    endtask

endmodule
