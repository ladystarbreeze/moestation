/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "iop.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

#include "cop0.hpp"
#include "gte.hpp"
#include "../bus/bus.hpp"

namespace ps2::iop {

using Exception = cop0::Exception;

/* --- IOP constants --- */

constexpr u32 RESET_VECTOR = 0xBFC00000;

constexpr auto doDisasm = false;
constexpr auto doPrintf = false;

bool doNewPrintf = false;

/* --- IOP register definitions --- */

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

/* --- IOP instructions --- */

enum Opcode {
    SPECIAL = 0x00,
    REGIMM  = 0x01,
    J       = 0x02,
    JAL     = 0x03,
    BEQ     = 0x04,
    BNE     = 0x05,
    BLEZ    = 0x06,
    BGTZ    = 0x07,
    ADDI    = 0x08,
    ADDIU   = 0x09,
    SLTI    = 0x0A,
    SLTIU   = 0x0B,
    ANDI    = 0x0C,
    ORI     = 0x0D,
    XORI    = 0x0E,
    LUI     = 0x0F,
    COP0    = 0x10,
    COP2    = 0x12,
    LB      = 0x20,
    LH      = 0x21,
    LWL     = 0x22,
    LW      = 0x23,
    LBU     = 0x24,
    LHU     = 0x25,
    LWR     = 0x26,
    SB      = 0x28,
    SH      = 0x29,
    SWL     = 0x2A,
    SW      = 0x2B,
    SWR     = 0x2E,
};

enum SPECIALOpcode {
    SLL     = 0x00,
    SRL     = 0x02,
    SRA     = 0x03,
    SLLV    = 0x04,
    SRLV    = 0x06,
    SRAV    = 0x07,
    JR      = 0x08,
    JALR    = 0x09,
    SYSCALL = 0x0C,
    MFHI    = 0x10,
    MTHI    = 0x11,
    MFLO    = 0x12,
    MTLO    = 0x13,
    MULT    = 0x18,
    MULTU   = 0x19,
    DIV     = 0x1A,
    DIVU    = 0x1B,
    ADD     = 0x20,
    ADDU    = 0x21,
    SUB     = 0x22,
    SUBU    = 0x23,
    AND     = 0x24,
    OR      = 0x25,
    XOR     = 0x26,
    NOR     = 0x27,
    SLT     = 0x2A,
    SLTU    = 0x2B,
};

enum REGIMMOpcode {
    BLTZ = 0x00,
    BGEZ = 0x01,
};

enum COPOpcode {
    MF  = 0x00,
    CF  = 0x02,
    MT  = 0x04,
    CT  = 0x06,
    CO  = 0x10,
};

enum COP0Opcode {
    RFE = 0x10,
};

/* --- IOP registers --- */

u32 regs[34]; // 32 GPRs, LO, HI

u32 pc, cpc, npc; // Program counters

bool inDelaySlot[2]; // Branch delay helper

u32 msgAddr;

bool inPS1Mode = false;

/* --- Register accessors --- */

/* Sets a CPU register */
void set(u32 idx, u32 data) {
    assert(idx < 34);

    regs[idx] = data;

    regs[0] = 0;
}

/* Sets PC and NPC to the same value */
void setPC(u32 addr) {
    if (addr == 0) {
        std::printf("[IOP       ] Jump to 0\n");

        exit(0);
    }

    if (addr & 3) {
        std::printf("[IOP       ] Misaligned PC: 0x%08X\n", addr);

        exit(0);
    }

    pc  = addr;
    npc = addr + 4;
}

/* Sets branch PC (NPC) */
void setBranchPC(u32 addr) {
    if (addr == 0) {
        std::printf("[IOP       ] Jump to 0\n");

        exit(0);
    }

    if (addr & 3) {
        std::printf("[IOP       ] Misaligned PC: 0x%08X\n", addr);

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

/* Reads a byte from memory */
u8 read8(u32 addr) {
    return bus::readIOP8(addr & 0x1FFFFFFF); // Masking the address like this should be fine
}

/* Reads a halfword from memory */
u16 read16(u32 addr) {
    assert(!(addr & 1));

    return bus::readIOP16(addr & 0x1FFFFFFF); // Masking the address like this should be fine
}

/* Reads a word from memory */
u32 read32(u32 addr) {
    assert(!(addr & 3));

    return bus::readIOP32(addr & 0x1FFFFFFF); // Masking the address like this should be fine
}

/* Fetches an instruction word, advances PC */
u32 fetchInstr() {
    const auto instr = read32(cpc);

    stepPC();

    return instr;
}

/* Writes a byte to memory */
void write8(u32 addr, u8 data) {
    if (doNewPrintf && (addr >= msgAddr)) {
        std::printf("%c", data);
    }

    return bus::writeIOP8(addr & 0x1FFFFFFF, data); // Masking the address like this should be fine
}

/* Writes a halfword to memory */
void write16(u32 addr, u16 data) {
    assert(!(addr & 1));

    return bus::writeIOP16(addr & 0x1FFFFFFF, data); // Masking the address like this should be fine
}

/* Writes a word to memory */
void write32(u32 addr, u32 data) {
    assert(!(addr & 3));

    return bus::writeIOP32(addr & 0x1FFFFFFF, data); // Masking the address like this should be fine
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
void doBranch(u32 target, bool isCond, u32 rd) {
    if (inDelaySlot[0]) {
        std::printf("[IOP       ] Branch instruction in delay slot\n");

        exit(0);
    }

    set(rd, npc);

    inDelaySlot[1] = true;

    if (isCond) {
        setBranchPC(target);
    }
}

/* Raises a CPU exception */
void raiseException(Exception e) {
    //std::printf("[IOP       ] %s exception @ 0x%08X\n", cop0::eNames[e], cpc);

    cop0::enterException(e); // Set exception code, save 

    u32 vector;
    if (cop0::isBEV()) { vector = 0xBFC00180; } else { vector = 0x80000080; }

    cop0::setBD(inDelaySlot[0]);

    if (inDelaySlot[0]) {
        cop0::setEPC(cpc - 4);
    } else {
        cop0::setEPC(cpc);
    }

    inDelaySlot[0] = false;
    inDelaySlot[1] = false;

    setPC(vector);
}

/* --- Instruction handlers --- */

/* ADD */
void iADD(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = regs[rs] + regs[rt];

    /* If rs and imm have the same sign and rs and the result have a different sign,
     * an arithmetic overflow occurred
     */
    if (!((regs[rs] ^ regs[rt]) & (1 << 31)) && ((regs[rs] ^ res) & (1 << 31))) {
        std::printf("[IOP       ] ADDI: Unhandled Arithmetic Overflow\n");

        exit(0);
    }

    set(rd, res);

    if (doDisasm) {
        std::printf("[IOP       ] ADD %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* ADD Immediate */
void iADDI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u32)(i16)getImm(instr);

    const auto res = regs[rs] + imm;

    /* If rs and imm have the same sign and rs and the result have a different sign,
     * an arithmetic overflow occurred
     */
    if (!((regs[rs] ^ imm) & (1 << 31)) && ((regs[rs] ^ res) & (1 << 31))) {
        std::printf("[IOP       ] ADDI: Unhandled Arithmetic Overflow\n");

        exit(0);
    }

    set(rt, res);

    if (doDisasm) {
        std::printf("[IOP       ] ADDI %s, %s, 0x%X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], res);
    }
}

/* ADD Immediate Unsigned */
void iADDIU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u32)(i16)getImm(instr);

    set(rt, regs[rs] + imm);

    if (doDisasm) {
        std::printf("[IOP       ] ADDIU %s, %s, 0x%X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]);
    }
}

/* ADD Unsigned */
void iADDU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rs] + regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] ADDU %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* AND */
void iAND(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rs] & regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] AND %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* AND Immediate */
void iANDI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = getImm(instr);

    set(rt, regs[rs] & imm);

    if (doDisasm) {
        std::printf("[IOP       ] ANDI %s, %s, 0x%X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]);
    }
}

/* Branch if EQual */
void iBEQ(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, regs[rs] == regs[rt], CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] BEQ %s, %s, 0x%08X; %s = 0x%08X, %s = 0x%08X\n", regNames[rs], regNames[rt], target, regNames[rs], regs[rs], regNames[rt], regs[rt]);
    }
}

/* Branch if Greater than or Equal Zero */
void iBGEZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i32)regs[rs] >= 0, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] BGEZ %s, 0x%08X; %s = 0x%08X\n", regNames[rs], target, regNames[rs], regs[rs]);
    }
}

/* Branch if Greater Than Zero */
void iBGTZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i32)regs[rs] > 0, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] BGTZ %s, 0x%08X; %s = 0x%08X\n", regNames[rs], target, regNames[rs], regs[rs]);
    }
}

/* Branch if Less than or Equal Zero */
void iBLEZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i32)regs[rs] <= 0, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] BLEZ %s, 0x%08X; %s = 0x%08X\n", regNames[rs], target, regNames[rs], regs[rs]);
    }
}

/* Branch if Less Than Zero */
void iBLTZ(u32 instr) {
    const auto rs = getRs(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, (i32)regs[rs] < 0, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] BLTZ %s, 0x%08X; %s = 0x%08X\n", regNames[rs], target, regNames[rs], regs[rs]);
    }
}

/* Branch if Not Equal */
void iBNE(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto offset = (i32)(i16)getImm(instr) << 2;
    const auto target = pc + offset;

    doBranch(target, regs[rs] != regs[rt], CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] BNE %s, %s, 0x%08X; %s = 0x%08X, %s = 0x%08X\n", regNames[rs], regNames[rt], target, regNames[rs], regs[rs], regNames[rt], regs[rt]);
    }
}

/* Coprocessor move From Control */
void iCFC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    u32 data;

    switch (copN) {
        case 2: data = gte::getControl(rd); break;
        default:
            std::printf("[IOP       ] CFC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    set(rt, data);

    if (doDisasm) {
        std::printf("[IOP       ] CFC%d %s, %d; %s = 0x%08X\n", copN, regNames[rt], rd, regNames[rt], regs[rt]);
    }
}

/* Coprocessor move To Control */
void iCTC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    const auto data = regs[rt];

    switch (copN) {
        case 2: gte::setControl(rd, data); break;
        default:
            std::printf("[IOP       ] CTC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    if (doDisasm) {
        std::printf("[IOP       ] CTC%d %s, %d; %d = 0x%08X\n", copN, regNames[rt], rd, rd, regs[rt]);
    }
}

/* DIVide */
void iDIV(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto n = (i32)regs[rs];
    const auto d = (i32)regs[rt];

    assert((d != 0) && !((n == INT32_MIN) && (d == -1)));

    regs[CPUReg::LO] = n / d;
    regs[CPUReg::HI] = n % d;

    if (doDisasm) {
        std::printf("[EE Core   ] DIV %s, %s; LO = 0x%08X, HI = 0x%08X\n", regNames[rs], regNames[rt], regs[CPUReg::LO], regs[CPUReg::HI]);
    }
}

/* DIVide Unsigned */
void iDIVU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto n = regs[rs];
    const auto d = regs[rt];

    assert(d != 0);

    regs[CPUReg::LO] = n / d;
    regs[CPUReg::HI] = n % d;

    if (doDisasm) {
        std::printf("[EE Core   ] DIVU %s, %s; LO = 0x%08X, HI = 0x%08X\n", regNames[rs], regNames[rt], regs[CPUReg::LO], regs[CPUReg::HI]);
    }
}

/* Jump */
void iJ(u32 instr) {
    const auto target = (pc & 0xF0000000) | (getOffset(instr) << 2);

    doBranch(target, true, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] J 0x%08X; PC = 0x%08X\n", target, target);
    }
}

/* Jump And Link */
void iJAL(u32 instr) {
    const auto target = (pc & 0xF0000000) | (getOffset(instr) << 2);

    doBranch(target, true, CPUReg::RA);

    if (doDisasm) {
        std::printf("[IOP       ] JAL 0x%08X; RA = 0x%08X, PC = 0x%08X\n", target, regs[CPUReg::RA], target);
    }
}

/* Jump And Link Register */
void iJALR(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);

    const auto target = regs[rs];

    doBranch(target, true, rd);

    if (doDisasm) {
        std::printf("[IOP       ] JALR %s, %s; %s = 0x%08X, PC = 0x%08X\n", regNames[rd], regNames[rs], regNames[rd], regs[rd], target);
    }
}

/* Jump Register */
void iJR(u32 instr) {
    const auto rs = getRs(instr);

    const auto target = regs[rs];

    doBranch(target, true, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] JR %s; PC = 0x%08X\n", regNames[rs], target);
    }
}

/* Load Byte */
void iLB(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LB %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    assert(!cop0::isCacheIsolated());

    set(rt, (i8)read8(addr));
}

/* Load Byte Unsigned */
void iLBU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LBU %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    assert(!cop0::isCacheIsolated());

    set(rt, read8(addr));
}

/* Load Halfword */
void iLH(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LH %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 1) {
        std::printf("[IOP       ] LH: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    assert(!cop0::isCacheIsolated());

    set(rt, (i16)read16(addr));
}

/* Load Halfword Unsigned */
void iLHU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LHU %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 1) {
        std::printf("[IOP       ] LHU: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    assert(!cop0::isCacheIsolated());

    set(rt, read16(addr));
}

/* Load Upper Immediate */
void iLUI(u32 instr) {
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr) << 16;

    set(rt, imm);

    if (doDisasm) {
        std::printf("[IOP       ] LUI %s, 0x%08X; %s = 0x%08X\n", regNames[rt], imm, regNames[rt], regs[rt]);
    }
}

/* Load Word */
void iLW(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LW %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    if (addr & 3) {
        std::printf("[IOP       ] LW: Unhandled AdEL @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    assert(!cop0::isCacheIsolated());

    set(rt, read32(addr));
}

/* Load Word Left */
void iLWL(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LWL %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    const auto shift = 24 - 8 * (addr & 3);
    const auto mask = ~(~0 << shift);

    set(rt, (regs[rt] & mask) | (read32(addr & ~3) << shift));
}

/* Load Word Right */
void iLWR(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    if (doDisasm) {
        std::printf("[IOP       ] LWR %s, 0x%X(%s); %s = [0x%08X]\n", regNames[rt], imm, regNames[rs], regNames[rt], addr);
    }

    const auto shift = 8 * (addr & 3);
    const auto mask = 0xFFFFFF00 << (24 - shift);

    set(rt, (regs[rt] & mask) | (read32(addr & ~3) >> shift));
}

/* Move From Coprocessor */
void iMFC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    u32 data;

    switch (copN) {
        case 0: data = cop0::get(rd); break;
        case 2: data = gte::get(rd); break;
        default:
            std::printf("[IOP       ] MFC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    set(rt, data);

    if (doDisasm) {
        std::printf("[IOP       ] MFC%d %s, %d; %s = 0x%08X\n", copN, regNames[rt], rd, regNames[rt], regs[rt]);
    }
}

/* Move From HI */
void iMFHI(u32 instr) {
    const auto rd = getRd(instr);

    set(rd, regs[CPUReg::HI]);

    if (doDisasm) {
        std::printf("[IOP       ] MFHI %s; %s = 0x%08X\n", regNames[rd], regNames[rd], regs[rd]);
    }
}

/* Move From LO */
void iMFLO(u32 instr) {
    const auto rd = getRd(instr);

    set(rd, regs[CPUReg::LO]);

    if (doDisasm) {
        std::printf("[IOP       ] MFLO %s; %s = 0x%08X\n", regNames[rd], regNames[rd], regs[rd]);
    }
}

/* Move To Coprocessor */
void iMTC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    const auto data = regs[rt];

    switch (copN) {
        case 0: cop0::set(rd, data); break;
        case 2: gte::set(rd, data); break;
        default:
            std::printf("[IOP       ] MTC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    if (doDisasm) {
        std::printf("[IOP       ] MTC%d %s, %d; %d = 0x%08X\n", copN, regNames[rt], rd, rd, regs[rt]);
    }
}

/* Move To HI */
void iMTHI(u32 instr) {
    const auto rs = getRs(instr);

    regs[CPUReg::HI] = regs[rs];

    if (doDisasm) {
        std::printf("[IOP       ] MTHI %s; HI = 0x%08X\n", regNames[rs], regs[rs]);
    }
}

/* Move To LO */
void iMTLO(u32 instr) {
    const auto rs = getRs(instr);

    regs[CPUReg::LO] = regs[rs];

    if (doDisasm) {
        std::printf("[IOP       ] MTLO %s; LO = 0x%08X\n", regNames[rs], regs[rs]);
    }
}

/* MULTiply */
void iMULT(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = (i64)(i32)regs[rs] * (i64)(i32)regs[rt];

    regs[CPUReg::LO] = res;
    regs[CPUReg::HI] = res >> 32;

    if (doDisasm) {
        std::printf("[IOP       ] MULT %s, %s; LO = 0x%08X, HI = 0x%08X\n", regNames[rs], regNames[rt], regs[CPUReg::LO], regs[CPUReg::HI]);
    }
}

/* MULTiply Unsigned */
void iMULTU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = (u64)regs[rs] * (u64)regs[rt];

    regs[CPUReg::LO] = res;
    regs[CPUReg::HI] = res >> 32;

    if (doDisasm) {
        std::printf("[IOP       ] MULTU %s, %s; LO = 0x%08X, HI = 0x%08X\n", regNames[rs], regNames[rt], regs[CPUReg::LO], regs[CPUReg::HI]);
    }
}

/* NOR */
void iNOR(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, ~(regs[rs] | regs[rt]));

    if (doDisasm) {
        std::printf("[IOP       ] NOR %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* OR */
void iOR(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rs] | regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] OR %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* OR Immediate */
void iORI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = getImm(instr);

    set(rt, regs[rs] | imm);

    if (doDisasm) {
        std::printf("[IOP       ] ORI %s, %s, 0x%X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]);
    }
}

/* Return From Exception */
void iRFE() {
    if (doDisasm) {
        std::printf("[IOP       ] RFE\n");
    }

    cop0::leaveException();
}

/* Store Byte */
void iSB(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;
    const auto data = (u8)regs[rt];

    if (doDisasm) {
        std::printf("[IOP       ] SB %s, 0x%X(%s); [0x%08X] = 0x%02X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    if (cop0::isCacheIsolated()) return;

    write8(addr, data);
}

/* Store Halfword */
void iSH(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;
    const auto data = (u16)regs[rt];

    if (doDisasm) {
        std::printf("[IOP       ] SH %s, 0x%X(%s); [0x%08X] = 0x%04X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    if (addr & 1) {
        std::printf("[IOP       ] SH: Unhandled AdES @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    if (cop0::isCacheIsolated()) return;

    write16(addr, data);
}

/* Shift Left Logical */
void iSLL(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set(rd, regs[rt] << shamt);

    if (doDisasm) {
        if (rd == CPUReg::R0) {
            std::printf("[IOP       ] NOP\n");
        } else {
            std::printf("[IOP       ] SLL %s, %s, %u; %s = 0x%08X\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]);
        }
    }
}

/* Shift Left Logical Variable */
void iSLLV(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rt] << (regs[rs] & 0x1F));

    if (doDisasm) {
        std::printf("[IOP       ] SLLV %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rt], regNames[rs], regNames[rd], regs[rd]);
    }
}

/* Set on Less Than */
void iSLT(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, (i32)regs[rs] < (i32)regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] SLT %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* Set on Less Than Immediate */
void iSLTI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    set(rt, (i32)regs[rs] < imm);

    if (doDisasm) {
        std::printf("[IOP       ] SLTI %s, %s, 0x%08X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]);
    }
}

/* Set on Less Than Immediate Unsigned */
void iSLTIU(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (u32)(i16)getImm(instr);

    set(rt, regs[rs] < imm);

    if (doDisasm) {
        std::printf("[IOP       ] SLTIU %s, %s, 0x%08X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]);
    }
}

/* Set on Less Than Unsigned */
void iSLTU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rs] < regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] SLTU %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* Shift Right Arithmetic */
void iSRA(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set(rd, (i32)regs[rt] >> shamt);

    if (doDisasm) {
         std::printf("[IOP       ] SRA %s, %s, %u; %s = 0x%08X\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]);
    }
}

/* Shift Right Arithmetic Variable */
void iSRAV(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, (i32)regs[rt] >> (regs[rs] & 0x1F));

    if (doDisasm) {
        std::printf("[IOP       ] SRAV %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rt], regNames[rs], regNames[rd], regs[rd]);
    }
}

/* Shift Right Logical */
void iSRL(u32 instr) {
    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    const auto shamt = getShamt(instr);

    set(rd, regs[rt] >> shamt);

    if (doDisasm) {
         std::printf("[IOP       ] SRL %s, %s, %u; %s = 0x%08X\n", regNames[rd], regNames[rt], shamt, regNames[rd], regs[rd]);
    }
}

/* Shift Right Logical Variable */
void iSRLV(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rt] >> (regs[rs] & 0x1F));

    if (doDisasm) {
        std::printf("[IOP       ] SRLV %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rt], regNames[rs], regNames[rd], regs[rd]);
    }
}

/* SUBtract */
void iSUB(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto res = regs[rs] - regs[rt];

    /* If rs and imm have different signs and rs and the result have a different sign,
     * an arithmetic overflow occurred
     */
    if (((regs[rs] ^ regs[rt]) & (1 << 31)) && ((regs[rs] ^ res) & (1 << 31))) {
        std::printf("[IOP       ] SUB: Unhandled Arithmetic Overflow\n");

        exit(0);
    }

    set(rd, res);

    if (doDisasm) {
        std::printf("[IOP       ] SUB %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* SUBtract Unsigned */
void iSUBU(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rs] - regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] SUBU %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* Store Word */
void iSW(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;
    const auto data = regs[rt];

    if (doDisasm) {
        std::printf("[IOP       ] SW %s, 0x%X(%s); [0x%08X] = 0x%08X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    if (addr & 3) {
        std::printf("[IOP       ] SW: Unhandled AdES @ 0x%08X (address = 0x%08X)\n", cpc, addr);

        exit(0);
    }

    if (cop0::isCacheIsolated()) return;

    write32(addr, data);
}

/* Store Word Left */
void iSWL(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    const auto shift = 8 * (addr & 3);
    const auto mask  = 0xFFFFFF00 << shift;

    const auto data = (read32(addr & ~3) & mask) | (regs[rt] >> (24 - shift));

    if (doDisasm) {
        std::printf("[IOP       ] SWL %s, 0x%X(%s); [0x%08X] = 0x%08X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    write32(addr & ~3, data);
}

/* Store Word Right */
void iSWR(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = (i32)(i16)getImm(instr);

    const auto addr = regs[rs] + imm;

    const auto shift = 8 * (addr & 3);
    const auto mask  = ~(~0 << shift);

    const auto data = (read32(addr & ~3) & mask) | (regs[rt] << shift);

    if (doDisasm) {
        std::printf("[IOP       ] SWR %s, 0x%X(%s); [0x%08X] = 0x%08X\n", regNames[rt], imm, regNames[rs], addr, data);
    }

    write32(addr & ~3, data);
}

/* SYStem CALL */
void iSYSCALL() {
    if (doDisasm) {
        std::printf("[IOP       ] SYSCALL\n");
    }

    raiseException(Exception::SystemCall);
}

/* XOR */
void iXOR(u32 instr) {
    const auto rd = getRd(instr);
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    set(rd, regs[rs] ^ regs[rt]);

    if (doDisasm) {
        std::printf("[IOP       ] XOR %s, %s, %s; %s = 0x%08X\n", regNames[rd], regNames[rs], regNames[rt], regNames[rd], regs[rd]);
    }
}

/* XOR Immediate */
void iXORI(u32 instr) {
    const auto rs = getRs(instr);
    const auto rt = getRt(instr);

    const auto imm = getImm(instr);

    set(rt, regs[rs] ^ imm);

    if (doDisasm) {
        std::printf("[IOP       ] XORI %s, %s, 0x%X; %s = 0x%08X\n", regNames[rt], regNames[rs], imm, regNames[rt], regs[rt]);
    }
}

void decodeInstr(u32 instr) {
    const auto opcode = getOpcode(instr);

    switch (opcode) {
        case Opcode::SPECIAL:
            {
                const auto funct = getFunct(instr);

                switch (funct) {
                    case SPECIALOpcode::SLL    : iSLL(instr); break;
                    case SPECIALOpcode::SRL    : iSRL(instr); break;
                    case SPECIALOpcode::SRA    : iSRA(instr); break;
                    case SPECIALOpcode::SLLV   : iSLLV(instr); break;
                    case SPECIALOpcode::SRLV   : iSRLV(instr); break;
                    case SPECIALOpcode::SRAV   : iSRAV(instr); break;
                    case SPECIALOpcode::JR     : iJR(instr); break;
                    case SPECIALOpcode::JALR   : iJALR(instr); break;
                    case SPECIALOpcode::SYSCALL: iSYSCALL(); break;
                    case SPECIALOpcode::MFHI   : iMFHI(instr); break;
                    case SPECIALOpcode::MTHI   : iMTHI(instr); break;
                    case SPECIALOpcode::MFLO   : iMFLO(instr); break;
                    case SPECIALOpcode::MTLO   : iMTLO(instr); break;
                    case SPECIALOpcode::MULT   : iMULT(instr); break;
                    case SPECIALOpcode::MULTU  : iMULTU(instr); break;
                    case SPECIALOpcode::DIV    : iDIV(instr); break;
                    case SPECIALOpcode::DIVU   : iDIVU(instr); break;
                    case SPECIALOpcode::ADD    : iADD(instr); break;
                    case SPECIALOpcode::ADDU   : iADDU(instr); break;
                    case SPECIALOpcode::SUB    : iSUB(instr); break;
                    case SPECIALOpcode::SUBU   : iSUBU(instr); break;
                    case SPECIALOpcode::AND    : iAND(instr); break;
                    case SPECIALOpcode::OR     : iOR(instr); break;
                    case SPECIALOpcode::XOR    : iXOR(instr); break;
                    case SPECIALOpcode::NOR    : iNOR(instr); break;
                    case SPECIALOpcode::SLT    : iSLT(instr); break;
                    case SPECIALOpcode::SLTU   : iSLTU(instr); break;
                    default:
                        std::printf("[IOP       ] Unhandled SPECIAL instruction 0x%02X (0x%08X) @ 0x%08X\n", funct, instr, cpc);

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
                        std::printf("[IOP       ] Unhandled REGIMM instruction 0x%02X (0x%08X) @ 0x%08X\n", rt, instr, cpc);

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
        case Opcode::ADDI : iADDI(instr); break;
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
                                case COP0Opcode::RFE: iRFE(); break;
                                default:
                                    std::printf("[IOP       ] Unhandled COP0 instruction 0x%02X (0x%08X) @ 0x%08X\n", funct, instr, cpc);

                                    exit(0);
                            }
                        }
                        break;
                    default:
                        std::printf("[IOP       ] Unhandled COP0 instruction 0x%02X (0x%08X) @ 0x%08X\n", rs, instr, cpc);

                        exit(0);
                }
            }
            break;
        case Opcode::COP2:
            {
                const auto rs = getRs(instr);

                if (rs >= COPOpcode::CO) {
                    gte::doCmd(instr & 0x1FFFFFF);
                } else {
                    switch (rs) {
                        case COPOpcode::MF: iMFC(2, instr); break;
                        case COPOpcode::CF: iCFC(2, instr); break;
                        case COPOpcode::MT: iMTC(2, instr); break;
                        case COPOpcode::CT: iCTC(2, instr); break;
                        default:
                            std::printf("[IOP       ] Unhandled COP2 instruction 0x%02X (0x%08X) @ 0x%08X\n", rs, instr, cpc);

                            exit(0);
                    }
                }
            }
            break;
        case Opcode::LB : iLB(instr); break;
        case Opcode::LH : iLH(instr); break;
        case Opcode::LWL: iLWL(instr); break;
        case Opcode::LW : iLW(instr); break;
        case Opcode::LBU: iLBU(instr); break;
        case Opcode::LHU: iLHU(instr); break;
        case Opcode::LWR: iLWR(instr); break;
        case Opcode::SB : iSB(instr); break;
        case Opcode::SH : iSH(instr); break;
        case Opcode::SWL: iSWL(instr); break;
        case Opcode::SW : iSW(instr); break;
        case Opcode::SWR: iSWR(instr); break;
        default:
            std::printf("[IOP       ] Unhandled instruction 0x%02X (0x%08X) @ 0x%08X\n", opcode, instr, cpc);

            exit(0);
    }
}

void init() {
    std::memset(&regs, 0, 34 * sizeof(u32));

    // Set program counter to reset vector
    setPC(RESET_VECTOR);

    // Initialize coprocessors
    cop0::init();

    std::printf("[IOP       ] Init OK\n");
}

void step(i64 c) {
    for (int i = c; i != 0; i--) {
        cpc = pc; // Save current PC

        if (!inPS1Mode && doPrintf && ((cpc == 0x12C48) || (cpc == 0x1420C) || (cpc == 0x1430C))) {
            auto ptr = regs[5];

            for (auto ctr = regs[6]; ctr > 0; ctr--) {
                std::printf("%c", read8(ptr & 0x1FFFFF));

                ptr++;
            }
        }

        // Advance delay slot helper
        inDelaySlot[0] = inDelaySlot[1];
        inDelaySlot[1] = false;

        /* Hook into BIOS functions */
        if (inPS1Mode && ((cpc == 0xA0) || (cpc == 0xB0) || (cpc == 0xC0))) {
            /* Get BIOS function */
            const auto funct = regs[CPUReg::T1];

            if ((cpc == 0xA0) && (funct == 0x40)) {
                std::printf("[CPU        ] SystemErrorUnresolvedException()\n"); // Bad.

                exit(0);
            } else if ((cpc == 0xB0) && (funct == 0x3D)) {
                /* putc */
                std::printf("%c", (char)regs[CPUReg::A0]);
            }
        }

        decodeInstr(fetchInstr());
    }
}

void enterPS1Mode() {
    std::printf("[IOP       ] Entering PS1 mode\n");

    cop0::setID(0xE);

    init();

    inPS1Mode = true;
}

void doInterrupt() {
    /* Set CPC and advance delay slot */
    cpc = pc;

    inDelaySlot[0] = inDelaySlot[1];
    inDelaySlot[1] = false;

    raiseException(Exception::Interrupt);
}

}
