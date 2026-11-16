//==========================================================================
// mem_blackbox.v - Memory stubs for synthesis
//
// Owner: Member E (infrastructure), reviewed by Member D
//
// For area and logic-depth figures we synthesise the CORE only and treat
// the two memories as external IP.  That matches how the design would be
// built on an FPGA: instruction and data memory become block RAM
// primitives, not fabric logic.  Synthesising the 1024-word arrays into
// flip-flops instead would report roughly 65,000 registers and completely
// swamp the datapath and control numbers we actually want to compare
// between configurations.
//
// These declarations are marked blackbox and carry no body, so Yosys
// keeps the instance as an interface and reports only the logic around
// it.  They are used INSTEAD OF rtl/common/imem.v and rtl/common/dmem.v
// and only during synthesis; simulation always uses the real modules.
//==========================================================================

(* blackbox *)
module imem #(
    parameter HEXFILE = ""
) (
    input  wire [31:0] addr,
    output wire [31:0] instr
);
endmodule

(* blackbox *)
module dmem #(
    parameter HEXFILE = ""
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire        we,
    input  wire        re,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
endmodule
