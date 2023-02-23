/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "vu_int.hpp"

#include <cassert>
#include <cstdio>

using VectorUnit = ps2::ee::vu::VectorUnit;

/* --- VU constants --- */

constexpr auto doDisasm = true;

/* --- VU instructions --- */

enum SPECIAL1Opcode {
    VSUB = 0x2C,
};

enum SPECIAL2Opcode {
    VSQI  = 0x35,
    VISWR = 0x3F,
};

/* --- VU instruction helpers --- */

const char *destStr[16] = {
    ""   , ".w"  , ".z"  , ".zw"  ,
    ".y" , ".yw" , ".yz" , ".yzw" ,
    ".x" , ".xw" , ".xz" , ".xzw" ,
    ".xy", ".xyw", ".xyz", ".xyzw",
};

/* Returns dest */
u32 getDest(u32 instr) {
    return (instr >> 21) & 0xF;
}

/* Returns {i/f}d */
u32 getD(u32 instr) {
    return (instr >> 6) & 0x1F;
}

/* Returns {i/f}s */
u32 getS(u32 instr) {
    return (instr >> 11) & 0x1F;
}

/* Returns {i/f}t */
u32 getT(u32 instr) {
    return (instr >> 16) & 0x1F;
}

/* --- VU instruction handlers --- */

/* Integer Store Word Register */
void iISWR(VectorUnit *vu, u32 instr) {
    const auto is = getS(instr);
    const auto it = getT(instr);

    const auto dest = getDest(instr);

    const auto addr = vu->getVI(is) << 4;
    const auto data = vu->getVI(it);

    if (doDisasm) {
        std::printf("[VU%d       ] ISWR%s VI%u, (VI%u)\n", vu->vuID, destStr[dest], it, is);
    }

    if (dest & (1 << 0)) vu->writeData32(addr + 0xC, data);
    if (dest & (1 << 1)) vu->writeData32(addr + 0x8, data);
    if (dest & (1 << 2)) vu->writeData32(addr + 0x4, data);
    if (dest & (1 << 3)) vu->writeData32(addr + 0x0, data);
}

/* Store Quadword Increment */
void iSQI(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto it = getT(instr);

    const auto dest = getDest(instr);

    const auto addr = vu->getVI(it) << 4;

    if (doDisasm) {
        std::printf("[VU%d       ] SQI%s VF%u%s, (VI%u)++\n", vu->vuID, destStr[dest], fs, destStr[dest], it);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) {
            const auto data = vu->getVF(fs, i);

            vu->writeData32(addr + 4 * i, *(u32 *)&data);
        }
    }

    vu->setVI(it, vu->getVI(it) + 1);
}

/* SUBtract */
void iSUB(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] SUB%s VF%u, VF%u, VF%u\n", vu->vuID, destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF(fs, i) - vu->getVF(ft, i));
    }
}

namespace ps2::ee::vu::interpreter {

/* Executes a COP2 instruction (VU0 only) */
void executeMacro(VectorUnit *vu, u32 instr) {
    assert(!vu->vuID);

    if ((instr & 0x3C) == 0x3C) {
        const auto opcode = ((instr >> 4) & 0x7C) | (instr & 3);

        switch (opcode) {
            case SPECIAL2Opcode::VSQI : iSQI(vu, instr); break;
            case SPECIAL2Opcode::VISWR: iISWR(vu, instr); break;
            default:
                std::printf("[VU%d       ] Unhandled SPECIAL2 macro instruction 0x%02X (0x%08X)\n", vu->vuID, opcode, instr);

                exit(0);
        }
    } else {
        const auto opcode = instr & 0x3F;

        switch (opcode) {
            case SPECIAL1Opcode::VSUB: iSUB(vu, instr); break;
            default:
                std::printf("[VU%d       ] Unhandled SPECIAL1 macro instruction 0x%02X (0x%08X)\n", vu->vuID, opcode, instr);

                exit(0);
        }
    }
}

}
