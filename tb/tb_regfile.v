//==========================================================================
// tb_regfile.v - Unit test for the register file
// Owner: Member E (Verification)
//
// Checks the two properties the pipeline depends on:
//   - x0 reads as zero and writes to x0 are discarded
//   - same-cycle write-to-read bypass (removes the WB->ID hazard)
//==========================================================================
`timescale 1ns/1ps
`include "defines.vh"

module tb_regfile;

    reg         clk = 0, rst = 1;
    reg  [4:0]  rs1_addr = 0, rs2_addr = 0, rd_addr = 0;
    reg         we = 0;
    reg  [31:0] rd_data = 0;
    wire [31:0] rs1_data, rs2_data;

    integer errors = 0;

    regfile dut (
        .clk(clk), .rst(rst),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .we(we), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    always #5 clk = ~clk;

    task expect1 (input [31:0] exp, input [8*40-1:0] name);
        begin
            if (rs1_data !== exp) begin
                $display("  FAIL %0s: got %0d expected %0d", name, rs1_data, exp);
                errors = errors + 1;
            end else $display("  pass %0s", name);
        end
    endtask

    initial begin
        $display("== tb_regfile ==");
        @(posedge clk); @(posedge clk);
        rst = 0;

        // write x5 = 42
        @(negedge clk);
        we = 1; rd_addr = 5; rd_data = 32'd42;
        @(posedge clk);
        @(negedge clk);
        we = 0; rs1_addr = 5;
        #1 expect1(32'd42, "write then read x5");

        // write to x0 must be discarded
        @(negedge clk);
        we = 1; rd_addr = 0; rd_data = 32'hDEADBEEF;
        @(posedge clk);
        @(negedge clk);
        we = 0; rs1_addr = 0;
        #1 expect1(32'd0, "write to x0 discarded");

        // same-cycle write-to-read bypass: read x7 while writing x7
        @(negedge clk);
        we = 1; rd_addr = 7; rd_data = 32'd1234; rs1_addr = 7;
        #1 expect1(32'd1234, "same-cycle WB->ID bypass");
        @(posedge clk);
        @(negedge clk);
        we = 0;
        #1 expect1(32'd1234, "value committed after the edge");

        // bypass must not fire when we is low
        @(negedge clk);
        we = 0; rd_addr = 7; rd_data = 32'd9999; rs1_addr = 7;
        #1 expect1(32'd1234, "no bypass when we=0");

        // bypass must not fire for a write to x0
        @(negedge clk);
        we = 1; rd_addr = 0; rd_data = 32'd555; rs1_addr = 0;
        #1 expect1(32'd0, "no bypass for x0 write");

        if (errors == 0) $display("== tb_regfile PASSED ==");
        else             $display("== tb_regfile FAILED (%0d errors) ==", errors);
        $finish;
    end

endmodule
