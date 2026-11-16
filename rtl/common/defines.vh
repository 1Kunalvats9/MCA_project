//==========================================================================
// defines.vh - shared constants for the RV32I subset processor
//
// Included by every RTL module so that opcodes, ALU control codes and
// memory sizes are defined in exactly one place.
//==========================================================================
`ifndef RV_DEFINES_VH
`define RV_DEFINES_VH

// ---- Datapath width ----------------------------------------------------
`define XLEN      32

// ---- RV32I opcodes (instr[6:0]) ---------------------------------------
`define OP_RTYPE  7'b0110011   // add, sub
`define OP_IARITH 7'b0010011   // addi  (also the NOP encoding)
`define OP_LOAD   7'b0000011   // lw
`define OP_STORE  7'b0100011   // sw
`define OP_BRANCH 7'b1100011   // beq, bne

// ---- funct3 fields ----------------------------------------------------
`define F3_ADD_SUB 3'b000      // add / sub / addi  (sub picked by funct7)
`define F3_LW_SW   3'b010
`define F3_BEQ     3'b000
`define F3_BNE     3'b001

// ---- funct7 fields ----------------------------------------------------
`define F7_ADD    7'b0000000
`define F7_SUB    7'b0100000

// ---- ALU control codes ------------------------------------------------
`define ALU_ADD   2'b00
`define ALU_SUB   2'b01

// ---- Write-back source select -----------------------------------------
`define WB_ALU    1'b0
`define WB_MEM    1'b1

// ---- Forwarding mux select codes --------------------------------------
`define FWD_REG   2'b00        // use the value read from the register file
`define FWD_MEM   2'b01        // forward from EX/MEM (ALU result)
`define FWD_WB    2'b10        // forward from MEM/WB (ALU result or load data)

// ---- Branch predictor: 2-bit saturating counter states ----------------
// The prediction is the top bit, so 10 and 11 predict taken.
`define BHT_STRONG_NT 2'b00
`define BHT_WEAK_NT   2'b01
`define BHT_WEAK_T    2'b10
`define BHT_STRONG_T  2'b11

// ---- Memory sizing ----------------------------------------------------
// Both memories are 1024 words (4 KiB).  Word-addressed internally; the
// datapath supplies a byte address and the memory drops the low two bits.
`define MEM_WORDS 1024
`define MEM_ADDR_BITS 10

`endif
