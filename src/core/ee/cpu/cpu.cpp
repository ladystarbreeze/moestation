/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "cpu.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

#include "cop0.hpp"

#include "../../bus/bus.hpp"

using namespace ps2::ee;

constexpr u32 RESET_VECTOR = 0xBFC00000;

constexpr auto doDisasm = false;

/* --- EE Core register definitions --- */

enum CPUReg {
    R0 =  0, AT =  1, V0 =  2, V1 =  3,
    A0 =  4, A1 =  5, A2 =  6, A3 =  7,
    T0 =  8, T1 =  9, T2 = 10, T3 = 11,
    T4 = 12, T5 = 13, T6 = 14, T7 = 15,
    S0 = 16, S1 = 17, S2 = 18, S3 = 19,
    S4 = 20, S5 = 21, S6 = 22, S7 = 23,
    T8 = 24, T9 = 25, K0 = 26, K1 = 27,
    GP = 28, SP = 29, S8 = 30, RA = 31,
    LO = 32, HI = 33,
};

const char *regNames[34] = {
    "R0", "AT", "V0", "V1", "A0", "A1", "A2", "A3",
    "T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7",
    "S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7",
    "T8", "T9", "K0", "K1", "GP", "SP", "S8", "RA",
    "LO", "HI"
};

/* --- EE Core instructions --- */

enum Opcode {
    SPECIAL = 0x00,
    REGIMM  = 0x01,
    J       = 0x02,
    JAL     = 0x03,
    BEQ     = 0x04,
    BNE     = 0x05,
    BLEZ    = 0x06,
    BGTZ    = 0x07,
    ADDIU   = 0x09,
    SLTI    = 0x0A,
    SLTIU   = 0x0B,
    ANDI    = 0x0C,
    ORI     = 0x0D,
    XORI    = 0x0E,
    LUI     = 0x0F,
    COP0    = 0x10,
    BEQL    = 0x14,
    BNEL    = 0x15,
    DADDIU  = 0x19,
    MMI     = 0x1C,
    LQ      = 0x1E,
    SQ      = 0x1F,
    LB      = 0x20,
    LH      = 0x21,
    LW      = 0x23,
    LBU     = 0x24,
    LHU     = 0x25,
    LWU     = 0x27,
    SB      = 0x28,
    SH      = 0x29,
    SW      = 0x2B,
    LD      = 0x37,
    SD      = 0x3F,
};

enum SPECIALOpcode {
    SLL    = 0x00,
    SRL    = 0x02,
    SRA    = 0x03,
    SLLV   = 0x04,
    JR     = 0x08,
    JALR   = 0x09,
    MOVZ   = 0x0A,
    MOVN   = 0x0B,
    SYNC   = 0x0F,
    MFHI   = 0x10,
    MFLO   = 0x12,
    DSLLV  = 0x14,
    DSRAV  = 0x17,
    MULT   = 0x18,
    DIV    = 0x1A,
    DIVU   = 0x1B,
    ADDU   = 0x21,
    SUBU   = 0x23,
    AND    = 0x24,
    OR     = 0x25,
    SLT    = 0x2A,
    SLTU   = 0x2B,
    DADDU  = 0x2D,
    DSLL   = 0x38,
    DSRL   = 0x3A,
    DSLL32 = 0x3C,
    DSRL32 = 0x3E,
    DSRA32 = 0x3F,
};

enum REGIMMOpcode {
    BLTZ = 0x00,
    BGEZ = 0x01,
};

enum COPOpcode {
    MF = 0x00,
    MT = 0x04,
    CO = 0x10,
};

enum COP0Opcode {
    TLBWI = 0x02,
};

enum MMIOpcode {
    MFLO1 = 0x12,
    MULT1 = 0x18,
    DIV1  = 0x1A,
    DIVU1 = 0x1B,
    MMI3  = 0x29,
};

enum MMI3Opcode {
    PAND = 0x12,
};

/* --- EE Core registers --- */

u128 regs[34]; // GPRs, LO, HI

u32 pc, cpc, npc; // Program counters

u8 sa; // Shift amount

bool inDelaySlot[2]; // Branch delay helper

u8 spram[0x4000]; // Scratchpad RAM

/* --- Register accessors --- */

/* Sets a CPU register (32-bit) */
void set32(u32 idx, u32 data) {
    assert(idx < 34);

    regs[idx].lo = (i32)data; // Sign extension is important here!!

    regs[0].lo = 0;
    regs[0].hi = 0;
}

/* Sets a CPU register (64-bit) */
void set64(u32 idx, u64 data) {
    assert(idx < 34);

    regs[idx].lo = data;

    regs[0].lo = 0;
    regs[0].hi = 0;
}

/* Sets a CPU register (128-bit) */
void set128(u32 idx, const u128 &data) {
    assert(idx < 34);

    regs[idx] = data;

    regs[0].lo = 0;
    regs[0].hi = 0;
}

/* Sets PC and NPC to the same value */
void setPC(u32 addr) {
    if (addr == 0) {
        std::printf("[EE Core   ] Jump to 0\n");

        exit(0);
    }

    if (addr & 3) {
        std::printf("[EE Core   ] Misaligned PC: 0x%08X\n", addr);

        exit(0);
    }

    pc  = addr;
    npc = addr + 4;
}

/* Sets branch PC (NPC) */
void setBranchPC(u32 addr) {
    if (addr == 0) {
        std::printf("[EE Core   ] Jump to 0\n");

        exit(0);
    }

    if (addr & 3) {
        std::printf("[EE Core   ] Misaligned PC: 0x%08X\n", addr);

        exit(0);
    }

    npc = addr;
}

/* Advances PC */
void stepPC() {
    pc = npc;

    npc += 4;
}

/* --- Memory accessors --- */

/* Translates a virtual address to a physical address */
u32 translateAddr(u32 addr) {
    if (addr >= 0xFFFF8000) {
        std::printf("[EE Core   ] Unhandled TLB mapped region @ 0x%08X\n", addr);

        exit(0);
    } else {
        addr &= (1 << 29) - 1;
    }

    return addr;
}

/* Reads a byte from scratchpad RAM */
u8 readSPRAM8(u32 addr) {
    addr &= 0x3FFF;

    return spram[addr];
}

/* Reads a byte from memory */
u8 read8(u32 addr) {
    if ((addr >> 28) == 0x7) return readSPRAM8(addr);

    return ps2::bus::read8(translateAddr(addr));
}

/* Reads a halfword from scratchpad RAM */
u16 readSPRAM16(u32 addr) {
    u16 data;

    addr &= 0x3FFE;

    std::memcpy(&data, &spram[addr], sizeof(u16));

    return data;
}

/* Reads a halfword from memory */
u32 read16(u32 addr) {
    assert(!(addr & 1));

    if ((addr >> 28) == 0x7) return readSPRAM16(addr);

    return ps2::bus::read16(translateAddr(addr));
}

/* Reads a word from scratchpad RAM */
u32 readSPRAM32(u32 addr) {
    u32 data;

    addr &= 0x3FFC;

    std::memcpy(&data, &spram[addr], sizeof(u32));

    return data;
}

/* Reads a word from memory */
u32 read32(u32 addr) {
    assert(!(addr & 3));

    if ((addr >> 28) == 0x7) return readSPRAM32(addr);

    return ps2::bus::read32(translateAddr(addr));
}

/* Reads a doubleword from scratchpad RAM */
u64 readSPRAM64(u32 addr) {
    u64 data;

    addr &= 0x3FF8;

    std::memcpy(&data, &spram[addr], sizeof(u64));

    return data;
}

/* Reads a doubleword from memory */
u64 read64(u32 addr) {
    assert(!(addr & 7));

    if ((addr >> 28) == 0x7) return readSPRAM64(addr);

    return ps2::bus::read64(translateAddr(addr));
}

/* Reads a quadword from scratchpad RAM */
u128 readSPRAM128(u32 addr) {
    u128 data;

    addr &= 0x3FF0;

    std::memcpy(&data, &spram[addr], sizeof(u128));

    return data;
}

/* Reads a quadword from memory */
u128 read128(u32 addr) {
    assert(!(addr & 15));

    if ((addr >> 28) == 0x7) return readSPRAM128(addr);

    return ps2::bus::read128(translateAddr(addr));
}

/* Fetches an instruction word, advances PC */
u32 fetchInstr() {
    const auto instr = read32(cpc);

    stepPC();

    return instr;
}

/* Writes a byte to scratchpad RAM */
void writeSPRAM8(u32 addr, u32 data) {
    addr &= 0x3FFF;

    spram[addr] = data;
}

/* Writes a byte to memory */
void write8(u32 addr, u32 data) {
    if ((addr >> 28) == 0x7) return writeSPRAM8(addr, data);

    ps2::bus::write8(translateAddr(addr), data);
}

/* Writes a halfword to scratchpad RAM */
void writeSPRAM16(u32 addr, u16 data) {
    addr &= 0x3FFE;

    std::memcpy(&spram[addr], &data, sizeof(u16));
}

/* Writes a halfword to memory */
void write16(u32 addr, u32 data) {
    assert(!(addr & 1));

    if ((addr >> 28) == 0x7) return writeSPRAM16(addr, data);

    ps2::bus::write16(translateAddr(addr), data);
}

/* Writes a word to scratchpad RAM */
void writeSPRAM32(u32 addr, u32 data) {
    addr &= 0x3FFC;

    std::memcpy(&spram[addr], &data, sizeof(u32));
}

/* Writes a word to memory */
void write32(u32 addr, u32 data) {
    assert(!(addr & 3));

    if ((addr >> 28) == 0x7) return writeSPRAM32(addr, data);

    ps2::bus::write32(translateAddr(addr), data);
}

/* Writes a doubleword to scratchpad RAM */
void writeSPRAM64(u32 addr, u64 data) {
    addr &= 0x3FF8;

    std::memcpy(&spram[addr], &data, sizeof(u64));
}

/* Writes a doubleword to memory */
void write64(u32 addr, u64 data) {
    assert(!(addr & 7));

    if ((addr >> 28) == 0x7) return writeSPRAM64(addr, data);

    ps2::bus::write64(translateAddr(addr), data);
}

/* Writes a quadword to scratchpad RAM */
void writeSPRAM128(u32 addr, const u128 &data) {
    addr &= 0x3FF0;

    std::memcpy(&spram[addr], &data, sizeof(u128));
}

/* Writes a quadword to memory */
void write128(u32 addr, const u128 &data) {
    assert(!(addr & 15));

    if ((addr >> 28) == 0x7) return writeSPRAM128(addr, data);

    ps2::bus::write128(translateAddr(addr), data);
}

/* --- Instruction helpers --- */

/* Returns Opcode field */
u32 getOpcode(u32 instr) {
    return instr >> 26;
}

/* Returns Funct field */
u32 getFunct(u32 instr) {
    return instr & 0x3F;
}

/* Returns Shamt field */
u32 getShamt(u32 instr) {
    return (instr >> 6) & 0x1F;
}

/* Returns 16-bit immediate */
u32 getImm(u32 instr) {
    return instr & 0xFFFF;
}

/* Returns 26-bit immediate */
u32 getOffset(u32 instr) {
    return instr & 0x3FFFFFF;
}

/* Returns Rd field */
u32 getRd(u32 instr) {
    return (instr >> 11) & 0x1F;
}

/* Returns Rs field */
u32 getRs(u32 instr) {
    return (instr >> 21) & 0x1F;
}

/* Returns Rt field */
u32 getRt(u32 instr) {
    return (instr >> 16) & 0x1F;
}

/* Executes branches */
void doBranch(u32 target, bool isCond, u32 rd, bool isLikely) {
    if (inDelaySlot[0]) {
        std::printf("[EE Core   ] Branch instruction in delay slot\n");

        exit(0);
    }

    set32(rd, npc);

    inDelaySlot[1] = true;

    if (isCond) {
        setBranchPC(target);
    } else if (isLikely) {
        setPC(npc);

        inDelaySlot[1] = false;
    }
}

/* --- Instruction handlers --- */

/* ADD Immediate Unsigned */
void iADDIU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u32)(i16)getImm(instr);

    set32(rt, regs[rs]._u32[0] + imm);

    if (doDisasm) {
        std::printf("[EE Core   ] ADDIU %s, %s, 0x%X; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* ADD Unsigned */
void iADDU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set32(rd, regs[rs]._u32[0] + regs[rt]._u32[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] ADDU %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* AND */
void iAND(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, regs[rs]._u64[0] & regs[rt]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] AND %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* AND Immediate */
void iANDI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u64)getImm(instr);

    set64(rt, regs[rs]._u64[0] & imm);

    if (doDisasm) {
        std::printf("[EE Core   ] ANDI %s, %s, 0x%llX; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Branch if EQual */
void iBEQ(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, regs[rs]._u64[0] == regs[rt]._u64[0], CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] BEQ %s, %s, 0x%08X; %s = 0x%016llX, %s = 0x%016llX\n", regNames[rs], regNames[rt], target, regNames[rs], (u64)rs, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Branch if EQual Likely */
void iBEQL(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, regs[rs]._u64[0] == regs[rt]._u64[0], CPUReg::R0, true);

    if (doDisasm) {
        std::printf("[EE Core   ] BEQL %s, %s, 0x%08X; %s = 0x%016llX, %s = 0x%016llX\n", regNames[rs], regNames[rt], target, regNames[rs], (u64)rs, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Branch if Greater than or Equal Zero */
void iBGEZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i64)regs[rs]._u64[0] >= 0, CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] BGEZ %s, 0x%08X; %s = 0x%016llX\n", regNames[rs], target, regNames[rs], (u64)rs);
    }
}

/* Branch if Greater Than Zero */
void iBGTZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i64)regs[rs]._u64[0] > 0, CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] BGTZ %s, 0x%08X; %s = 0x%016llX\n", regNames[rs], target, regNames[rs], (u64)rs);
    }
}

/* Branch if Less than or Equal Zero */
void iBLEZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i64)regs[rs]._u64[0] <= 0, CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] BLEZ %s, 0x%08X; %s = 0x%016llX\n", regNames[rs], target, regNames[rs], (u64)rs);
    }
}

/* Branch if Less Than Zero */
void iBLTZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i64)regs[rs]._u64[0] < 0, CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] BLTZ %s, 0x%08X; %s = 0x%016llX\n", regNames[rs], target, regNames[rs], (u64)rs);
    }
}

/* Branch if Not Equal */
void iBNE(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, regs[rs]._u64[0] != regs[rt]._u64[0], CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] BNE %s, %s, 0x%08X; %s = 0x%016llX, %s = 0x%016llX\n", regNames[rs], regNames[rt], target, regNames[rs], (u64)rs, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Branch if Not Equal Likely */
void iBNEL(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, regs[rs]._u64[0] != regs[rt]._u64[0], CPUReg::R0, true);

    if (doDisasm) {
        std::printf("[EE Core   ] BNEL %s, %s, 0x%08X; %s = 0x%016llX, %s = 0x%016llX\n", regNames[rs], regNames[rt], target, regNames[rs], (u64)rs, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Doubleword ADD Immediate Unsigned */
void iDADDIU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u64)(i16)getImm(instr);

    set64(rt, regs[rs]._u64[0] + imm);

    if (doDisasm) {
        std::printf("[EE Core   ] DADDIU %s, %s, 0x%llX; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Doubleword ADD Unsigned */
void iDADDU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, regs[rs]._u64[0] + regs[rt]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] DADDU %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* DIVide */
void iDIV(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto n = (i32)regs[rs]._u32[0];
    const auto d = (i32)regs[rt]._u32[0];

    assert((d != 0) && !((n == INT32_MIN) && (d == -1)));

    regs[CPUReg::LO]._u64[0] = n / d;
    regs[CPUReg::HI]._u64[0] = n % d;

    if (doDisasm) {
        std::printf("[EE Core   ] DIV %s, %s; LO = 0x%016llX, HI = 0x%016llX\n", regNames[rs], regNames[rt], regs[CPUReg::LO]._u64[0], regs[CPUReg::HI]._u64[0]);
    }
}

/* DIVide (logical pipeline 1) */
void iDIV1(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto n = (i32)regs[rs]._u32[0];
    const auto d = (i32)regs[rt]._u32[0];

    assert((d != 0) && !((n == INT32_MIN) && (d == -1)));

    regs[CPUReg::LO]._u64[1] = n / d;
    regs[CPUReg::HI]._u64[1] = n % d;

    if (doDisasm) {
        std::printf("[EE Core   ] DIV1 %s, %s; LO = 0x%016llX, HI = 0x%016llX\n", regNames[rs], regNames[rt], regs[CPUReg::LO]._u64[1], regs[CPUReg::HI]._u64[1]);
    }
}

/* DIVide Unsigned */
void iDIVU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto n = regs[rs]._u32[0];
    const auto d = regs[rt]._u32[0];

    assert(d != 0);

    regs[CPUReg::LO]._u64[0] = (i32)(n / d);
    regs[CPUReg::HI]._u64[0] = (i32)(n % d);

    if (doDisasm) {
        std::printf("[EE Core   ] DIVU %s, %s; LO = 0x%016llX, HI = 0x%016llX\n", regNames[rs], regNames[rt], regs[CPUReg::LO]._u64[0], regs[CPUReg::HI]._u64[0]);
    }
}

/* DIVide Unsigned (logical pipeline 1) */
void iDIVU1(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto n = regs[rs]._u32[0];
    const auto d = regs[rt]._u32[0];

    assert(d != 0);

    regs[CPUReg::LO]._u64[1] = (i32)(n / d);
    regs[CPUReg::HI]._u64[1] = (i32)(n % d);

    if (doDisasm) {
        std::printf("[EE Core   ] DIVU1 %s, %s; LO = 0x%016llX, HI = 0x%016llX\n", regNames[rs], regNames[rt], regs[CPUReg::LO]._u64[1], regs[CPUReg::HI]._u64[1]);
    }
}

/* Doubleword Shift Left Logical */
void iDSLL(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set64(rd, regs[rt]._u64[0] << shamt);

    if (doDisasm) {
        std::printf("[EE Core   ] DSLL %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* Doubleword Shift Left Logical Variable */
void iDSLLV(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, regs[rt]._u64[0] << (regs[rs]._u64[0] & 0x3F));

    if (doDisasm) {
        std::printf("[EE Core   ] DSLLV %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rt], regNames[rs], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Doubleword Shift Left Logical plus 32 */
void iDSLL32(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set64(rd, regs[rt]._u64[0] << (shamt + 32));

    if (doDisasm) {
        std::printf("[EE Core   ] DSLL32 %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* Doubleword Shift Right Arithmetic Variable */
void iDSRAV(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, (i64)regs[rt]._u64[0] >> (regs[rs]._u64[0] & 0x3F));

    if (doDisasm) {
        std::printf("[EE Core   ] DSRAV %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rt], regNames[rs], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Doubleword Shift Right Arithmetic plus 32 */
void iDSRA32(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set64(rd, (i64)regs[rt]._u64[0] >> (shamt + 32));

    if (doDisasm) {
        std::printf("[EE Core   ] DSRA32 %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* Doubleword Shift Right Logical */
void iDSRL(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set64(rd, regs[rt]._u64[0] >> shamt);

    if (doDisasm) {
        std::printf("[EE Core   ] DSRL %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* Doubleword Shift Right Logical plus 32 */
void iDSRL32(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set64(rd, regs[rt]._u64[0] >> (shamt + 32));

    if (doDisasm) {
        std::printf("[EE Core   ] DSRL32 %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* Jump */
void iJ(u32 instr) {
    const auto target = (pc & 0xF0000000) | (getOffset(instr) << 2);

    doBranch(target, true, CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] J 0x%08X; PC = 0x%08X\n", target, target);
    }
}

/* Jump And Link */
void iJAL(u32 instr) {
    const auto target = (pc & 0xF0000000) | (getOffset(instr) << 2);

    doBranch(target, true, CPUReg::RA, false);

    if (doDisasm) {
        std::printf("[EE Core   ] JAL 0x%08X; RA = 0x%016llX, PC = 0x%08X\n", target, regs[CPUReg::RA]._u64[0], target);
    }
}

/* Jump And Link Register */
void iJALR(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);

    const auto target = regs[rs]._u32[0];

    doBranch(target, true, rd, false);

    if (doDisasm) {
        std::printf("[EE Core   ] JALR %s, %s; %s = 0x%016llX, PC = 0x%08X\n", regNames[rd], regNames[rs], regNames[rd], regs[rd]._u64[0], target);
    }
}

/* Jump Register */
void iJR(u32 instr) {
    const auto rs = getRs(instr);

    const auto target = regs[rs]._u32[0];

    doBranch(target, true, CPUReg::R0, false);

    if (doDisasm) {
        std::printf("[EE Core   ] JR %s; PC = 0x%08X\n", regNames[rs], target);
    }
}

/* Load Byte */
void iLB(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LB %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    set64(rt, (i8)read8(addr));
}

/* Load Byte Unsigned */
void iLBU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LBU %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    set64(rt, read8(addr));
}

/* Load Doubleword */
void iLD(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LD %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 7) {
        std::printf("[EE Core   ] LD: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    set64(rt, read64(addr));
}

/* Load Halfword */
void iLH(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LH %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 1) {
        std::printf("[EE Core   ] LH: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    set32(rt, (i16)read16(addr));
}

/* Load Halfword Unsigned */
void iLHU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LHU %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 1) {
        std::printf("[EE Core   ] LHU: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    set64(rt, read16(addr));
}

/* Load Quadword */
void iLQ(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LQ %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 15) {
        std::printf("[EE Core   ] LQ: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    const auto data = read128(addr);

    set128(rt, data);
}

/* Load Upper Immediate */
void iLUI(u32 instr) {
    const auto rt = getRt(instr);

    const auto imm = (i64)(i16)getImm(instr) << 16;

    set64(rt, imm);

    if (doDisasm) {
        std::printf("[EE Core   ] LUI %s, 0x%08llX; %s = 0x%016llX\n", regNames[rt], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Load Word */
void iLW(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LW %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 3) {
        std::printf("[EE Core   ] LW: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    set32(rt, read32(addr));
}

/* Load Word Unsigned */
void iLWU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;

    if (doDisasm) {
        std::printf("[EE Core   ] LWU %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 3) {
        std::printf("[EE Core   ] LWU: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    set64(rt, read32(addr));
}

/* Move From Coprocessor */
void iMFC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    u32 data;

    switch (copN) {
        case 0: data = cop0::get32(rd); break;
        default:
            std::printf("[EE Core   ] MFC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    set32(rt, data);

    if (doDisasm) {
        std::printf("[EE Core   ] MFC%d %s, %d; %s = 0x%016llX\n", copN, regNames[rt], rd, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Move From HI */
void iMFHI(u32 instr) {
    const auto rd = getRd(instr);

    set64(rd, regs[CPUReg::HI]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] MFHI %s; %s = 0x%016llX\n", regNames[rd], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Move From LO */
void iMFLO(u32 instr) {
    const auto rd = getRd(instr);

    set64(rd, regs[CPUReg::LO]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] MFLO %s; %s = 0x%016llX\n", regNames[rd], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Move From LO (logical pipeline 1) */
void iMFLO1(u32 instr) {
    const auto rd = getRd(instr);

    set64(rd, regs[CPUReg::LO]._u64[1]);

    if (doDisasm) {
        std::printf("[EE Core   ] MFLO1 %s; %s = 0x%016llX\n", regNames[rd], regNames[rd], regs[rd]._u64[1]);
    }
}

/* MOVe on Not equal */
void iMOVN(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    if (regs[rt]._u64[0] != 0) set64(rd, regs[rs]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] MOVN %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* MOVe on Zero */
void iMOVZ(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    if (regs[rt]._u64[0] == 0) set64(rd, regs[rs]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] MOVZ %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Move To Coprocessor */
void iMTC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    const auto data = regs[rt]._u32[0];

    switch (copN) {
        case 0: cop0::set32(rd, data); break;
        default:
            std::printf("[EE Core   ] MTC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    if (doDisasm) {
        std::printf("[EE Core   ] MTC%d %s, %d; %d = 0x%08X\n", copN, regNames[rt], rd, rd, regs[rt]._u32[0]);
    }
}

/* MULTiply */
void iMULT(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = (i64)(i32)regs[rs]._u32[0] * (i64)(i32)regs[rt]._u32[0];

    regs[CPUReg::LO]._u64[0] = (i32)res;
    regs[CPUReg::HI]._u64[0] = (i32)(res >> 32);

    set64(rd, regs[CPUReg::LO]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] MULT %s, %s, %s; %s/LO = 0x%016llX, HI = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[CPUReg::LO]._u64[0], regs[CPUReg::HI]._u64[0]);
    }
}

/* MULTiply (logical pipeline 1) */
void iMULT1(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = (i64)(i32)regs[rs]._u32[0] * (i64)(i32)regs[rt]._u32[0];

    regs[CPUReg::LO]._u64[1] = (i32)res;
    regs[CPUReg::HI]._u64[1] = (i32)(res >> 32);

    set64(rd, regs[CPUReg::LO]._u64[1]);

    if (doDisasm) {
        std::printf("[EE Core   ] MULT1 %s, %s, %s; %s/LO = 0x%016llX, HI = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[CPUReg::LO]._u64[1], regs[CPUReg::HI]._u64[1]);
    }
}

/* OR */
void iOR(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, regs[rs]._u64[0] | regs[rt]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] OR %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* OR Immediate */
void iORI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u64)getImm(instr);

    set64(rt, regs[rs]._u64[0] | imm);

    if (doDisasm) {
        std::printf("[EE Core   ] ORI %s, %s, 0x%llX; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Parallel AND */
void iPAND(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = u128{{regs[rs]._u64[0] & regs[rt]._u64[0], regs[rs]._u64[1] & regs[rt]._u64[1]}};

    set128(rd, res);

    if (doDisasm) {
        std::printf("[EE Core   ] PAND %s, %s, %s; %s = 0x%016llX%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[1], regs[rd]._u64[0]);
    }
}

/* Store Byte */
void iSB(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;
    const auto data = regs[rt]._u8[0];

    if (doDisasm) {
        std::printf("[EE Core   ] SB %s, 0x%X(%s); [0x%08X] = 0x%02X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    write8(addr, data);
}

/* Store Doubleword */
void iSD(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;
    const auto data = regs[rt]._u64[0];

    if (doDisasm) {
        std::printf("[EE Core   ] SD %s, 0x%X(%s); [0x%08X] = 0x%016llX\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    if (addr & 7) {
        std::printf("[EE Core   ] SD: Unhandled AdES @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    write64(addr, data);
}

/* Store Halfword */
void iSH(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;
    const auto data = regs[rt]._u16[0];

    if (doDisasm) {
        std::printf("[EE Core   ] SH %s, 0x%X(%s); [0x%08X] = 0x%04X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    if (addr & 1) {
        std::printf("[EE Core   ] SH: Unhandled AdES @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    write16(addr, data);
}

/* Shift Left Logical */
void iSLL(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set32(rd, regs[rt]._u32[0] << shamt);

    if (doDisasm) {
        if (rd == CPUReg::R0) {
            std::printf("[EE Core   ] NOP\n");
        } else {
            std::printf("[EE Core   ] SLL %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
        }
    }
}

/* Shift Left Logical Variable */
void iSLLV(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set32(rd, regs[rt]._u32[0] << (regs[rs]._u64[0] & 0x1F));

    if (doDisasm) {
        std::printf("[EE Core   ] SLLV %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rt], regNames[rs], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Set on Less Than */
void iSLT(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, (i64)regs[rs]._u64[0] < (i64)regs[rt]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] SLT %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Set on Less Than Immediate */
void iSLTI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i64)(i16)getImm(instr);

    set64(rt, (i64)regs[rs]._u64[0] < imm);

    if (doDisasm) {
        std::printf("[EE Core   ] SLTI %s, %s, 0x%llX; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Set on Less Than Immediate Unsigned */
void iSLTIU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u64)(i16)getImm(instr);

    set64(rt, regs[rs]._u64[0] < imm);

    if (doDisasm) {
        std::printf("[EE Core   ] SLTIU %s, %s, 0x%llX; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

/* Set on Less Than Unsigned */
void iSLTU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set64(rd, regs[rs]._u64[0] < regs[rt]._u64[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] SLTU %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Store Quadword */
void iSQ(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;
    const auto data = regs[rt];

    if (doDisasm) {
        std::printf("[EE Core   ] SQ %s, 0x%X(%s); [0x%08X] = 0x%016llX%016llX\n", regNames[rt], imm, regNames[rs], addr, data._u64[1], data._u64[0]);
    }

    if (addr & 15) {
        std::printf("[EE Core   ] SQ: Unhandled AdES @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    write128(addr, data);
}

/* Shift Right Arithmetic */
void iSRA(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set32(rd, (i32)regs[rt]._u32[0] >> shamt);

    if (doDisasm) {
        std::printf("[EE Core   ] SRA %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* Shift Right Logical */
void iSRL(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set32(rd, regs[rt]._u32[0] >> shamt);

    if (doDisasm) {
        std::printf("[EE Core   ] SRL %s, %s, %u; %s = 0x%016llX\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]._u64[0]);
    }
}

/* SUBtract Unsigned */
void iSUBU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set32(rd, regs[rs]._u32[0] - regs[rt]._u32[0]);

    if (doDisasm) {
        std::printf("[EE Core   ] SUBU %s, %s, %s; %s = 0x%016llX\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]._u64[0]);
    }
}

/* Store Word */
void iSW(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs]._u32[0] + imm;
    const auto data = regs[rt]._u32[0];

    if (doDisasm) {
        std::printf("[EE Core   ] SW %s, 0x%X(%s); [0x%08X] = 0x%08X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    if (addr & 3) {
        std::printf("[EE Core   ] SW: Unhandled AdES @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    write32(addr, data);
}

/* SYNChronize */
void iSYNC(u32 instr) {
    const auto stype = getShamt(instr);

    if (doDisasm) {
        std::printf("[EE Core   ] SYNC.%s\n", (stype & (1 << 4)) ? "P" : "L");
    }
}

/* TLB Write Indexed */
void iTLBWI() {
    /* TODO: implement the TLB? */

    if (doDisasm) {
        std::printf("[EE Core   ] TLBWI\n");
    }
}

/* XOR Immediate */
void iXORI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u64)getImm(instr);

    set64(rt, regs[rs]._u64[0] ^ imm);

    if (doDisasm) {
        std::printf("[EE Core   ] XORI %s, %s, 0x%llX; %s = 0x%016llX\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]._u64[0]);
    }
}

void decodeInstr(u32 instr) {
    const auto opcode = getOpcode(instr);

    switch (opcode) {
        case Opcode::SPECIAL:
            {
                const auto funct = getFunct(instr);

                switch (funct) {
                    case SPECIALOpcode::SLL   : iSLL(instr); break;
                    case SPECIALOpcode::SRL   : iSRL(instr); break;
                    case SPECIALOpcode::SRA   : iSRA(instr); break;
                    case SPECIALOpcode::SLLV  : iSLLV(instr); break;
                    case SPECIALOpcode::JR    : iJR(instr); break;
                    case SPECIALOpcode::JALR  : iJALR(instr); break;
                    case SPECIALOpcode::MOVZ  : iMOVZ(instr); break;
                    case SPECIALOpcode::MOVN  : iMOVN(instr); break;
                    case SPECIALOpcode::SYNC  : iSYNC(instr); break;
                    case SPECIALOpcode::MFHI  : iMFHI(instr); break;
                    case SPECIALOpcode::MFLO  : iMFLO(instr); break;
                    case SPECIALOpcode::DSLLV : iDSLLV(instr); break;
                    case SPECIALOpcode::DSRAV : iDSRAV(instr); break;
                    case SPECIALOpcode::MULT  : iMULT(instr); break;
                    case SPECIALOpcode::DIV   : iDIV(instr); break;
                    case SPECIALOpcode::DIVU  : iDIVU(instr); break;
                    case SPECIALOpcode::ADDU  : iADDU(instr); break;
                    case SPECIALOpcode::SUBU  : iSUBU(instr); break;
                    case SPECIALOpcode::AND   : iAND(instr); break;
                    case SPECIALOpcode::OR    : iOR(instr); break;
                    case SPECIALOpcode::SLT   : iSLT(instr); break;
                    case SPECIALOpcode::SLTU  : iSLTU(instr); break;
                    case SPECIALOpcode::DADDU : iDADDU(instr); break;
                    case SPECIALOpcode::DSLL  : iDSLL(instr); break;
                    case SPECIALOpcode::DSRL  : iDSRL(instr); break;
                    case SPECIALOpcode::DSLL32: iDSLL32(instr); break;
                    case SPECIALOpcode::DSRL32: iDSRL32(instr); break;
                    case SPECIALOpcode::DSRA32: iDSRA32(instr); break;
                    default:
                        std::printf("[EE Core   ] Unhandled SPECIAL instruction 0x%02X (0x%08X) @ 0x%08X\n", funct, instr, cpc);

                        exit(0);
                }
            }
            break;
        case Opcode::REGIMM:
            {
                const auto rt = getRt(instr);

                switch (rt) {
                    case REGIMMOpcode::BLTZ: iBLTZ(instr); break;
                    case REGIMMOpcode::BGEZ: iBGEZ(instr); break;
                    default:
                        std::printf("[EE Core   ] Unhandled REGIMM instruction 0x%02X (0x%08X) @ 0x%08X\n", rt, instr, cpc);

                        exit(0);
                }
            }
            break;
        case Opcode::J    : iJ(instr); break;
        case Opcode::JAL  : iJAL(instr); break;
        case Opcode::BEQ  : iBEQ(instr); break;
        case Opcode::BNE  : iBNE(instr); break;
        case Opcode::BLEZ : iBLEZ(instr); break;
        case Opcode::BGTZ : iBGTZ(instr); break;
        case Opcode::ADDIU: iADDIU(instr); break;
        case Opcode::SLTI : iSLTI(instr); break;
        case Opcode::SLTIU: iSLTIU(instr); break;
        case Opcode::ANDI : iANDI(instr); break;
        case Opcode::ORI  : iORI(instr); break;
        case Opcode::XORI : iXORI(instr); break;
        case Opcode::LUI  : iLUI(instr); break;
        case Opcode::COP0 :
            {
                const auto rs = getRs(instr);

                switch (rs) {
                    case COPOpcode::MF: iMFC(0, instr); break;
                    case COPOpcode::MT: iMTC(0, instr); break;
                    case COPOpcode::CO:
                        {
                            const auto funct = getFunct(instr);

                            switch (funct) {
                                case COP0Opcode::TLBWI: iTLBWI(); break;
                                default:
                                    std::printf("[EE Core   ] Unhandled COP0 control instruction 0x%02X (0x%08X) @ 0x%08X\n", funct, instr, cpc);

                                    exit(0);
                            }
                        }
                        break;
                    default:
                        std::printf("[EE Core   ] Unhandled COP0 instruction 0x%02X (0x%08X) @ 0x%08X\n", rs, instr, cpc);

                        exit(0);
                }
            }
            break;
        case Opcode::BEQL  : iBEQL(instr); break;
        case Opcode::BNEL  : iBNEL(instr); break;
        case Opcode::DADDIU: iDADDIU(instr); break;
        case Opcode::MMI   :
            {
                const auto funct = getFunct(instr);

                switch (funct) {
                    case MMIOpcode::MFLO1: iMFLO1(instr); break;
                    case MMIOpcode::MULT1: iMULT1(instr); break;
                    case MMIOpcode::DIV1 : iDIV1(instr); break;
                    case MMIOpcode::DIVU1: iDIVU1(instr); break;
                    case MMIOpcode::MMI3 :
                        {
                            const auto shamt = getShamt(instr);

                            switch (shamt) {
                                case MMI3Opcode::PAND: iPAND(instr); break;
                                default:
                                    std::printf("[EE Core   ] Unhandled MMI3 instruction 0x%02X (0x%08X) @ 0x%08X\n", shamt, instr, cpc);

                                    exit(0);
                            }
                        }
                        break;
                    default:
                        std::printf("[EE Core   ] Unhandled MMI instruction 0x%02X (0x%08X) @ 0x%08X\n", funct, instr, cpc);

                        exit(0);
                }
            }
            break;
        case Opcode::LQ : iLQ(instr); break;
        case Opcode::SQ : iSQ(instr); break;
        case Opcode::LB : iLB(instr); break;
        case Opcode::LH : iLH(instr); break;
        case Opcode::LW : iLW(instr); break;
        case Opcode::LBU: iLBU(instr); break;
        case Opcode::LHU: iLHU(instr); break;
        case Opcode::LWU: iLWU(instr); break;
        case Opcode::SB : iSB(instr); break;
        case Opcode::SH : iSH(instr); break;
        case Opcode::SW : iSW(instr); break;
        case 0x2F       : break; // CACHE
        case Opcode::LD : iLD(instr); break;
        case 0x39       : break; // SWC1
        case Opcode::SD : iSD(instr); break;
        default:
            std::printf("[EE Core   ] Unhandled instruction 0x%02X (0x%08X) @ 0x%08X\n", opcode, instr, cpc);

            exit(0);
    }
}

namespace ps2::ee::cpu {

void init() {
    std::memset(&regs, 0, 34 * sizeof(u128));

    // Set program counter to reset vector
    setPC(RESET_VECTOR);

    // Initialize coprocessors
    cop0::init();

    std::printf("[EE Core   ] Init OK\n");
}

void step(i64 c) {
    for (int i = c; i != 0; i--) {
        cpc = pc; // Save current PC

        // Advance delay slot helper
        inDelaySlot[0] = inDelaySlot[1];
        inDelaySlot[1] = false;

        decodeInstr(fetchInstr());
    }

    cop0::incrementCount(c);
}

}