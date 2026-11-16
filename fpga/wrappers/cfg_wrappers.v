//==========================================================================
// cfg_wrappers.v - One wrapper per configuration, for the Vivado flow
//
// Owner: Member E (infrastructure)
//
// Why wrappers instead of synth_design -generic:
//
//   1. Each configuration becomes a distinct top module, so the Tcl flow
//      is a plain loop over four names with nothing configuration-
//      specific in it.
//   2. The parameter values are visible in source and can be checked by
//      reading this file, rather than being trusted to a command-line
//      flag that may silently not apply.
//   3. All four present an IDENTICAL port list, so one constraints file
//      covers every run.  The single-cycle core has no pipeline-only
//      observation signals, so those outputs are tied low in its wrapper.
//
// The memory initialisation filenames are deliberately BARE relative
// names.  run_vivado.tcl copies the chosen program's hex images into the
// Vivado run directory under exactly these names and runs with that
// directory as the working directory, so $readmemh resolves without any
// absolute paths being baked into the RTL.
//
// Initialising the instruction memory matters more than it looks: with an
// empty image every word reads as zero, the halt word, and the
// synthesiser would correctly optimise most of the processor away.  The
// utilisation figures would then be meaningless.  So a real program is
// always loaded, and run_vivado.tcl reports which one.
//==========================================================================
`include "defines.vh"

//--------------------------------------------------------------------------
// Configuration 1: single-cycle reference
//--------------------------------------------------------------------------
module cfg_single (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        retire_valid,
    output wire        stall_cycle,
    output wire        flush_event,
    output wire        branch_event,
    output wire        branch_taken,
    output wire        halted
);
    riscv_single_cycle #(
        .IMEM_HEX ("imem_init.hex"),
        .DMEM_HEX ("dmem_init.hex")
    ) u_core (
        .clk          (clk),
        .rst          (rst),
        .pc_out       (pc),
        .instr_out    (instr),
        .retire_valid (retire_valid),
        .halted       (halted)
    );

    // The single-cycle core has no pipeline, so these have no meaning.
    // Tied low rather than removed so that one constraints file and one
    // Tcl loop serve all four configurations.
    assign stall_cycle  = 1'b0;
    assign flush_event  = 1'b0;
    assign branch_event = 1'b0;
    assign branch_taken = 1'b0;
endmodule

//--------------------------------------------------------------------------
// Configuration 2: pipelined, no forwarding, static not-taken
//--------------------------------------------------------------------------
module cfg_stall (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        retire_valid,
    output wire        stall_cycle,
    output wire        flush_event,
    output wire        branch_event,
    output wire        branch_taken,
    output wire        halted
);
    riscv_pipeline #(
        .IMEM_HEX   ("imem_init.hex"),
        .DMEM_HEX   ("dmem_init.hex"),
        .FORWARD_EN (0),
        .PREDICTOR  (0)
    ) u_core (
        .clk          (clk),
        .rst          (rst),
        .if_pc        (pc),
        .wb_instr     (instr),
        .retire_valid (retire_valid),
        .stall_cycle  (stall_cycle),
        .flush_event  (flush_event),
        .branch_event (branch_event),
        .branch_taken (branch_taken),
        .halted       (halted)
    );
endmodule

//--------------------------------------------------------------------------
// Configuration 3: pipelined, full forwarding, static not-taken
//--------------------------------------------------------------------------
module cfg_fwd (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        retire_valid,
    output wire        stall_cycle,
    output wire        flush_event,
    output wire        branch_event,
    output wire        branch_taken,
    output wire        halted
);
    riscv_pipeline #(
        .IMEM_HEX   ("imem_init.hex"),
        .DMEM_HEX   ("dmem_init.hex"),
        .FORWARD_EN (1),
        .PREDICTOR  (0)
    ) u_core (
        .clk          (clk),
        .rst          (rst),
        .if_pc        (pc),
        .wb_instr     (instr),
        .retire_valid (retire_valid),
        .stall_cycle  (stall_cycle),
        .flush_event  (flush_event),
        .branch_event (branch_event),
        .branch_taken (branch_taken),
        .halted       (halted)
    );
endmodule

//--------------------------------------------------------------------------
// Configuration 4: pipelined, forwarding + 2-bit branch predictor
//--------------------------------------------------------------------------
module cfg_pred (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] pc,
    output wire [31:0] instr,
    output wire        retire_valid,
    output wire        stall_cycle,
    output wire        flush_event,
    output wire        branch_event,
    output wire        branch_taken,
    output wire        halted
);
    riscv_pipeline #(
        .IMEM_HEX       ("imem_init.hex"),
        .DMEM_HEX       ("dmem_init.hex"),
        .FORWARD_EN     (1),
        .PREDICTOR      (1),
        .BHT_INDEX_BITS (6)
    ) u_core (
        .clk          (clk),
        .rst          (rst),
        .if_pc        (pc),
        .wb_instr     (instr),
        .retire_valid (retire_valid),
        .stall_cycle  (stall_cycle),
        .flush_event  (flush_event),
        .branch_event (branch_event),
        .branch_taken (branch_taken),
        .halted       (halted)
    );
endmodule
