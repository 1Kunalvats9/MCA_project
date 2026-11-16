//==========================================================================
// tb_alu.v - Unit test for the ALU
// Owner: Member E (Verification)
//==========================================================================
`timescale 1ns/1ps
`include "defines.vh"

module tb_alu;

    reg  [1:0]  alu_ctrl;
    reg  [31:0] a, b;
    wire [31:0] result;
    wire        zero;

    integer errors = 0;

    alu dut (.alu_ctrl(alu_ctrl), .a(a), .b(b), .result(result), .zero(zero));

    task check (input [31:0] exp, input [8*32-1:0] name);
        begin
            #1;
            if (result !== exp) begin
                $display("  FAIL %0s: a=%0d b=%0d ctrl=%b -> %0d, expected %0d",
                         name, $signed(a), $signed(b), alu_ctrl,
                         $signed(result), $signed(exp));
                errors = errors + 1;
            end else begin
                $display("  pass %0s", name);
            end
        end
    endtask

    initial begin
        $display("== tb_alu ==");

        alu_ctrl = `ALU_ADD; a = 32'd7;  b = 32'd5;  check(32'd12,  "add 7+5");
        alu_ctrl = `ALU_ADD; a = 32'd0;  b = 32'd0;  check(32'd0,   "add 0+0");
        alu_ctrl = `ALU_SUB; a = 32'd7;  b = 32'd5;  check(32'd2,   "sub 7-5");
        alu_ctrl = `ALU_SUB; a = 32'd5;  b = 32'd7;  check(-32'd2,  "sub 5-7 negative");
        alu_ctrl = `ALU_SUB; a = 32'd9;  b = 32'd9;  check(32'd0,   "sub equal -> 0");

        // zero flag
        #1;
        if (zero !== 1'b1) begin
            $display("  FAIL zero flag not set on equal operands");
            errors = errors + 1;
        end else $display("  pass zero flag");

        // overflow / wraparound is defined two's complement behaviour
        alu_ctrl = `ALU_ADD; a = 32'h7FFFFFFF; b = 32'd1;
        check(32'h80000000, "add overflow wraps");

        // sign extension interaction: negative immediate
        alu_ctrl = `ALU_ADD; a = 32'd100; b = -32'd4;
        check(32'd96, "add with negative operand");

        if (errors == 0) $display("== tb_alu PASSED ==");
        else             $display("== tb_alu FAILED (%0d errors) ==", errors);
        $finish;
    end

endmodule
