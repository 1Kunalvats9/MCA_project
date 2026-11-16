#!/usr/bin/env python3
"""
asm.py - Minimal assembler for the RV32I subset used by this project.

Supported instructions : add sub addi lw sw beq bne nop
Supported directives   : .text  .data  .word
Labels                 : "name:" on its own line or before an instruction

Usage:
    python3 tools/asm.py programs/foo.s
        -> programs/foo.imem.hex   (instruction memory image)
        -> programs/foo.dmem.hex   (data memory image, all zeros if no .data)
        -> programs/foo.lst        (listing: pc / encoding / source)

Hex image format: one 32-bit word per line, 8 lowercase hex digits, no prefix.
This is the format expected by $readmemh in rtl/common/imem.v and dmem.v.
"""

import sys
import os
import re

# ---------------------------------------------------------------------------
# Instruction encoding tables
# ---------------------------------------------------------------------------
R_TYPE = {  # name: (funct7, funct3)
    'add': (0b0000000, 0b000),
    'sub': (0b0100000, 0b000),
}
I_ARITH = {  # name: funct3
    'addi': 0b000,
}
I_LOAD = {
    'lw': 0b010,
}
S_TYPE = {
    'sw': 0b010,
}
B_TYPE = {
    'beq': 0b000,
    'bne': 0b001,
}

OPCODE_R     = 0b0110011
OPCODE_IARIT = 0b0010011
OPCODE_LOAD  = 0b0000011
OPCODE_STORE = 0b0100011
OPCODE_BRANCH = 0b1100011


class AsmError(Exception):
    pass


def parse_reg(tok, lineno):
    """Accept x0..x31 (and the zero alias) and return the register number."""
    tok = tok.strip().lower()
    if tok == 'zero':
        return 0
    m = re.fullmatch(r'x(\d+)', tok)
    if not m:
        raise AsmError(f"line {lineno}: '{tok}' is not a register name")
    n = int(m.group(1))
    if not 0 <= n <= 31:
        raise AsmError(f"line {lineno}: register x{n} out of range")
    return n


def parse_imm(tok, lineno, bits, signed=True):
    """Parse a decimal / hex immediate and range-check it."""
    tok = tok.strip()
    try:
        val = int(tok, 0)
    except ValueError:
        raise AsmError(f"line {lineno}: '{tok}' is not an immediate value")
    if signed:
        lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    else:
        lo, hi = 0, (1 << bits) - 1
    if not lo <= val <= hi:
        raise AsmError(f"line {lineno}: immediate {val} does not fit in "
                       f"{bits} signed bits ({lo}..{hi})")
    return val & ((1 << bits) - 1)


def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm12, rs1, funct3, rd, opcode):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | \
           (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm12, rs2, rs1, funct3, opcode):
    imm12 &= 0xFFF
    hi = (imm12 >> 5) & 0x7F     # imm[11:5]
    lo = imm12 & 0x1F            # imm[4:0]
    return (hi << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (lo << 7) | opcode


def enc_b(off13, rs2, rs1, funct3, opcode):
    """off13 is the byte offset; bit 0 is always zero and is not encoded."""
    off13 &= 0x1FFF
    b12   = (off13 >> 12) & 0x1
    b10_5 = (off13 >> 5) & 0x3F
    b4_1  = (off13 >> 1) & 0xF
    b11   = (off13 >> 11) & 0x1
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


def split_operands(rest):
    """Split the operand list on commas, dropping empties."""
    return [t.strip() for t in rest.split(',') if t.strip()]


def parse_mem_operand(tok, lineno):
    """Parse the 'imm(rs1)' form used by lw and sw."""
    m = re.fullmatch(r'(-?\w+)\s*\(\s*(\w+)\s*\)', tok.strip())
    if not m:
        raise AsmError(f"line {lineno}: expected offset(register), got '{tok}'")
    return m.group(1), m.group(2)


def strip_comment(line):
    for marker in ('#', '//', ';'):
        idx = line.find(marker)
        if idx >= 0:
            line = line[:idx]
    return line.strip()


# ---------------------------------------------------------------------------
# Pass 1: collect labels and the item list
# ---------------------------------------------------------------------------
def pass1(lines):
    """Return (text_items, data_words, labels).

    text_items is a list of (pc, lineno, mnemonic, operand_string, source).
    data_words is a list of (lineno, value).
    labels maps a label name to a byte address in instruction memory.
    """
    text_items = []
    data_words = []
    labels = {}
    section = 'text'
    pc = 0

    for lineno, raw in enumerate(lines, start=1):
        line = strip_comment(raw)
        if not line:
            continue

        # One or more leading labels.
        while True:
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$', line)
            if not m:
                break
            name, line = m.group(1), m.group(2).strip()
            if name in labels:
                raise AsmError(f"line {lineno}: label '{name}' defined twice")
            if section != 'text':
                raise AsmError(f"line {lineno}: labels are only supported in .text")
            labels[name] = pc
        if not line:
            continue

        parts = line.split(None, 1)
        mnem = parts[0].lower()
        rest = parts[1] if len(parts) > 1 else ''

        if mnem == '.text':
            section = 'text'
            continue
        if mnem == '.data':
            section = 'data'
            continue
        if mnem == '.word':
            if section != 'data':
                raise AsmError(f"line {lineno}: .word is only allowed in .data")
            for tok in split_operands(rest):
                try:
                    data_words.append((lineno, int(tok, 0) & 0xFFFFFFFF))
                except ValueError:
                    raise AsmError(f"line {lineno}: '{tok}' is not a valid .word value")
            continue

        if section != 'text':
            raise AsmError(f"line {lineno}: instruction '{mnem}' found in .data")

        text_items.append((pc, lineno, mnem, rest, line))
        pc += 4

    return text_items, data_words, labels


# ---------------------------------------------------------------------------
# Pass 2: encode
# ---------------------------------------------------------------------------
def pass2(text_items, labels):
    words = []
    for pc, lineno, mnem, rest, src in text_items:
        ops = split_operands(rest)

        if mnem == 'nop':
            # Canonical RISC-V NOP is addi x0, x0, 0.
            word = enc_i(0, 0, 0b000, 0, OPCODE_IARIT)

        elif mnem in R_TYPE:
            if len(ops) != 3:
                raise AsmError(f"line {lineno}: {mnem} needs rd, rs1, rs2")
            funct7, funct3 = R_TYPE[mnem]
            rd  = parse_reg(ops[0], lineno)
            rs1 = parse_reg(ops[1], lineno)
            rs2 = parse_reg(ops[2], lineno)
            word = enc_r(funct7, rs2, rs1, funct3, rd, OPCODE_R)

        elif mnem in I_ARITH:
            if len(ops) != 3:
                raise AsmError(f"line {lineno}: {mnem} needs rd, rs1, imm")
            rd  = parse_reg(ops[0], lineno)
            rs1 = parse_reg(ops[1], lineno)
            imm = parse_imm(ops[2], lineno, 12)
            word = enc_i(imm, rs1, I_ARITH[mnem], rd, OPCODE_IARIT)

        elif mnem in I_LOAD:
            if len(ops) != 2:
                raise AsmError(f"line {lineno}: {mnem} needs rd, offset(rs1)")
            rd = parse_reg(ops[0], lineno)
            off_tok, base_tok = parse_mem_operand(ops[1], lineno)
            imm = parse_imm(off_tok, lineno, 12)
            rs1 = parse_reg(base_tok, lineno)
            word = enc_i(imm, rs1, I_LOAD[mnem], rd, OPCODE_LOAD)

        elif mnem in S_TYPE:
            if len(ops) != 2:
                raise AsmError(f"line {lineno}: {mnem} needs rs2, offset(rs1)")
            rs2 = parse_reg(ops[0], lineno)
            off_tok, base_tok = parse_mem_operand(ops[1], lineno)
            imm = parse_imm(off_tok, lineno, 12)
            rs1 = parse_reg(base_tok, lineno)
            word = enc_s(imm, rs2, rs1, S_TYPE[mnem], OPCODE_STORE)

        elif mnem in B_TYPE:
            if len(ops) != 3:
                raise AsmError(f"line {lineno}: {mnem} needs rs1, rs2, label")
            rs1 = parse_reg(ops[0], lineno)
            rs2 = parse_reg(ops[1], lineno)
            target = ops[2]
            if target in labels:
                off = labels[target] - pc
            else:
                try:
                    off = int(target, 0)
                except ValueError:
                    raise AsmError(f"line {lineno}: unknown branch target '{target}'")
            if off % 2 != 0:
                raise AsmError(f"line {lineno}: branch offset {off} is not even")
            if not -4096 <= off <= 4094:
                raise AsmError(f"line {lineno}: branch offset {off} out of range")
            word = enc_b(off, rs2, rs1, B_TYPE[mnem], OPCODE_BRANCH)

        else:
            raise AsmError(f"line {lineno}: unsupported instruction '{mnem}'")

        words.append((pc, word, src))
    return words


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    src_path = sys.argv[1]
    with open(src_path) as f:
        lines = f.read().splitlines()

    try:
        text_items, data_words, labels = pass1(lines)
        words = pass2(text_items, labels)
    except AsmError as e:
        print(f"{src_path}: error: {e}", file=sys.stderr)
        return 1

    base, _ = os.path.splitext(src_path)
    imem_path = base + '.imem.hex'
    dmem_path = base + '.dmem.hex'
    lst_path  = base + '.lst'

    with open(imem_path, 'w') as f:
        for _, word, _ in words:
            f.write(f"{word:08x}\n")

    with open(dmem_path, 'w') as f:
        for _, val in data_words:
            f.write(f"{val:08x}\n")

    with open(lst_path, 'w') as f:
        f.write(f"# listing for {src_path}\n")
        f.write(f"# {len(words)} instructions, {len(data_words)} data words\n")
        f.write("#   pc    encoding   source\n")
        for pc, word, src in words:
            f.write(f"{pc:6d}  {word:08x}   {src}\n")
        if labels:
            f.write("\n# labels\n")
            for name, addr in sorted(labels.items(), key=lambda kv: kv[1]):
                f.write(f"#   {name:<12} = {addr}\n")

    print(f"{src_path}: {len(words)} instructions, {len(data_words)} data words")
    print(f"  -> {imem_path}")
    print(f"  -> {dmem_path}")
    print(f"  -> {lst_path}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
