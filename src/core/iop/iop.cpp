/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "iop.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

#include "cop0.hpp"
#include "../bus/bus.hpp"

namespace ps2::iop {

/* --- IOP constants --- */

constexpr u32 RESET_VECTOR = 0xBFC00000;

constexpr auto doDisasm = true;

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
    BNE     = 0x05,
    SLTI    = 0x0A,
    ORI     = 0x0D,
    LUI     = 0x0F,
    COP0    = 0x10,
};

enum SPECIALOpcode {
    SLL = 0x00,
    JR  = 0x08,
};

enum COPOpcode {
    MF  = 0x00,
};

/* --- IOP registers --- */

u32 regs[34]; // 32 GPRs, LO, HI

u32 pc, cpc, npc; // Program counters

bool inDelaySlot[2]; // Branch delay helper

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

/* --- Instruction handlers --- */

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

/* Jump Register */
void iJR(u32 instr) {
    const auto rs = getRs(instr);

    const auto target = regs[rs];

    doBranch(target, true, CPUReg::R0);

    if (doDisasm) {
        std::printf("[IOP       ] JR %s; PC = 0x%08X\n", regNames[rs], target);
    }
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

/* Move From Coprocessor */
void iMFC(int copN, u32 instr) {
    assert((copN >= 0) && (copN < 4));

    const auto rd = getRd(instr);
    const auto rt = getRt(instr);

    /* TODO: add COP usable check */

    u32 data;

    switch (copN) {
        case 0: data = cop0::get(rd); break;
        default:
            std::printf("[IOP       ] MFC: Unhandled coprocessor %d\n", copN);

            exit(0);
    }

    set(rt, data);

    if (doDisasm) {
        std::printf("[IOP       ] MFC%d %s, %d; %s = 0x%08X\n", copN, regNames[rt], rd, regNames[rt], regs[rt]);
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

void decodeInstr(u32 instr) {
    const auto opcode = getOpcode(instr);

    switch (opcode) {
        case Opcode::SPECIAL:
            {
                const auto funct = getFunct(instr);

                switch (funct) {
                    case SPECIALOpcode::SLL: iSLL(instr); break;
                    case SPECIALOpcode::JR : iJR(instr); break;
                    default:
                        std::printf("[IOP       ] Unhandled SPECIAL instruction 0x%02X (0x%08X) @ 0x%08X\n", funct, instr, cpc);

                        exit(0);
                }
            }
            break;
        case Opcode::BNE : iBNE(instr); break;
        case Opcode::SLTI: iSLTI(instr); break;
        case Opcode::ORI : iORI(instr); break;
        case Opcode::LUI : iLUI(instr); break;
        case Opcode::COP0:
            {
                const auto rs = getRs(instr);

                switch (rs) {
                    case COPOpcode::MF: iMFC(0, instr); break;
                    default:
                        std::printf("[IOP       ] Unhandled COP0 instruction 0x%02X (0x%08X) @ 0x%08X\n", rs, instr, cpc);

                        exit(0);
                }
            }
            break;
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

        // Advance delay slot helper
        inDelaySlot[0] = inDelaySlot[1];
        inDelaySlot[1] = false;

        decodeInstr(fetchInstr());
    }
}

}
