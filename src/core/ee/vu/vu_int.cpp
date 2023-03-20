/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "vu_int.hpp"

#include <cassert>
#include <cmath>
#include <cstdio>

namespace ps2::ee::vu::interpreter {

/* --- VU constants --- */

constexpr auto doDisasm = true;
constexpr auto ACC = 32;

/* --- VU instructions --- */

enum SPECIAL1Opcode {
    VADDBC  = 0x00,
    VSUBBC  = 0x04,
    VMADDBC = 0x08,
    VMULBC  = 0x18,
    VMULQ   = 0x1C,
    VADDQ   = 0x20,
    VADD    = 0x28,
    VMUL    = 0x2A,
    VSUB    = 0x2C,
    VOPMSUB = 0x2E,
    VIADD   = 0x30,
};

enum SPECIAL2Opcode {
    VMADDABC = 0x08,
    VFTOI4   = 0x15,
    VMULABC  = 0x18,
    VOPMULA  = 0x2E,
    VNOP     = 0x2F,
    VMOVE    = 0x30,
    VMR32    = 0x31,
    VSQI     = 0x35,
    VDIV     = 0x38,
    VSQRT    = 0x39,
    VWAITQ   = 0x3B,
    VISWR    = 0x3F,
};

/* --- VU instruction helpers --- */

const char *destStr[16] = {
    ""   , ".w"  , ".z"  , ".zw"  ,
    ".y" , ".yw" , ".yz" , ".yzw" ,
    ".x" , ".xw" , ".xz" , ".xzw" ,
    ".xy", ".xyw", ".xyz", ".xyzw",
};

const char *bcStr[4] = { "x", "y", "z", "w" };

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

/* ADD */
void iADD(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] ADD%s VF%u, VF%u, VF%u\n", vu->vuID, destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) + vu->getVF_F32(ft, i));
    }
}

/* ADD with BroadCast */
void iADDbc(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto bc = instr & 3;

    const auto t = vu->getVF_F32(ft, bc);

    if (doDisasm) {
        std::printf("[VU%d       ] ADD%s%s VF%u, VF%u, VF%u\n", vu->vuID, bcStr[bc], destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) + t);
    }
}

/* ADD Q */
void iADDQ(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] ADD%s VF%u, VF%u, Q\n", vu->vuID, destStr[dest], fd, fs);
    }

    const auto q = vu->getQ();

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) + q);
    }
}

/* DIVide */
void iDIV(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto fsf = dest & 3;
    const auto ftf = dest >> 2;

    if (doDisasm) {
        std::printf("[VU%d       ] DIV Q, VF%u.%s, VF%u.%s\n", vu->vuID, fs, bcStr[fsf], ft, bcStr[ftf]);
    }

    vu->setQ(vu->getVF_F32(fs, fsf) / vu->getVF_F32(ft, ftf));
}

/* Float to Integer (28:)4 */
void iFTOI4(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] FTOI4%s VF%u, VF%u\n", vu->vuID, destStr[dest], fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        const auto data = (i32)std::round((vu->getVF_F32(fs, (i + 1) & 3)) * 16.0);
        
        if (dest & (1 << (3 - i))) vu->setVF(ft, i, *(u32 *)&data);
    }
}

/* Integer ADD */
void iIADD(VectorUnit *vu, u32 instr) {
    const auto id = getD(instr);
    const auto is = getS(instr);
    const auto it = getT(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] IADD VI%u, VI%u, VI%u\n", vu->vuID, id, is, it);
    }

    vu->setVI(id, vu->getVI(is) + vu->getVI(it));
}

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

/* Multiply-ADD to Accumulator with BroadCast */
void iMADDAbc(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto bc = instr & 3;

    const auto t = vu->getVF_F32(ft, bc);

    if (doDisasm) {
        std::printf("[VU%d       ] MADDA%s%s ACC, VF%u, VF%u\n", vu->vuID, bcStr[bc], destStr[dest], fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(ACC, i, vu->getVF_F32(fs, i) * t + vu->getVF_F32(ACC, i));
    }
}

/* Multiply-ADD with BroadCast */
void iMADDbc(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto bc = instr & 3;

    const auto t = vu->getVF_F32(ft, bc);

    if (doDisasm) {
        std::printf("[VU%d       ] MADD%s%s VF%u, VF%u, VF%u\n", vu->vuID, bcStr[bc], destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) * t + vu->getVF_F32(ACC, i));
    }
}

/* MOVE */
void iMOVE(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] MOVE%s VF%u, VF%u\n", vu->vuID, destStr[dest], fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fs, i, vu->getVF_F32(ft, i));
    }
}

/* Move Rotate 32 */
void iMR32(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] MR32%s VF%u, VF%u\n", vu->vuID, destStr[dest], fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fs, i, vu->getVF_F32(ft, (i + 1) & 3));
    }
}

/* MULtiply */
void iMUL(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] MUL%s VF%u, VF%u, VF%u\n", vu->vuID, destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) * vu->getVF_F32(ft, i));
    }
}

/* MULtiply to Accumulator with BroadCast */
void iMULAbc(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto bc = instr & 3;

    const auto t = vu->getVF_F32(ft, bc);

    if (doDisasm) {
        std::printf("[VU%d       ] MULA%s%s ACC, VF%u, VF%u\n", vu->vuID, bcStr[bc], destStr[dest], fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(ACC, i, vu->getVF_F32(fs, i) * t);
    }
}

/* MULtiply with BroadCast */
void iMULbc(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto bc = instr & 3;

    const auto t = vu->getVF_F32(ft, bc);

    if (doDisasm) {
        std::printf("[VU%d       ] MUL%s%s VF%u, VF%u, VF%u\n", vu->vuID, bcStr[bc], destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) * t);
    }
}

/* MULtiply Q */
void iMULQ(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] MUL%s VF%u, VF%u, Q\n", vu->vuID, destStr[dest], fd, fs);
    }

    const auto q = vu->getQ();

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) * q);
    }
}

/* NOP*/
void iNOP(VectorUnit *vu) {
    if (doDisasm) {
        std::printf("[VU%d       ] NOP\n", vu->vuID);
    }
}

/* Outer Product Multiply-SUBtract */
void iOPMSUB(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] OPMSUB%s VF%u, VF%u, VF%u\n", vu->vuID, destStr[dest], fd, fs, ft);
    }

    vu->setVF(fd, 0, vu->getVF_F32(ACC, 0) - vu->getVF_F32(fs, 1) * vu->getVF_F32(ft, 2));
    vu->setVF(fd, 1, vu->getVF_F32(ACC, 1) - vu->getVF_F32(fs, 2) * vu->getVF_F32(ft, 0));
    vu->setVF(fd, 2, vu->getVF_F32(ACC, 2) - vu->getVF_F32(fs, 0) * vu->getVF_F32(ft, 1));
}

/* Outer Product MULtiply to Accumulator */
void iOPMULA(VectorUnit *vu, u32 instr) {
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    if (doDisasm) {
        std::printf("[VU%d       ] OPMULA%s ACC, VF%u, VF%u\n", vu->vuID, destStr[dest], fs, ft);
    }

    vu->setVF(ACC, 0, vu->getVF_F32(fs, 1) * vu->getVF_F32(ft, 2));
    vu->setVF(ACC, 1, vu->getVF_F32(fs, 2) * vu->getVF_F32(ft, 0));
    vu->setVF(ACC, 2, vu->getVF_F32(fs, 0) * vu->getVF_F32(ft, 1));
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
            const auto data = vu->getVF_F32(fs, i);

            vu->writeData32(addr + 4 * i, *(u32 *)&data);
        }
    }

    vu->setVI(it, vu->getVI(it) + 1);
}

/* SQuare RooT */
void iSQRT(VectorUnit *vu, u32 instr) {
    const auto ft = getT(instr);

    const auto ftf = getDest(instr) >> 2;

    if (doDisasm) {
        std::printf("[VU%d       ] SQRT Q, VF%u.%s\n", vu->vuID, ft, bcStr[ftf]);
    }

    vu->setQ(std::sqrtf(vu->getVF_F32(ft, ftf)));
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
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) - vu->getVF_F32(ft, i));
    }
}

/* SUBtract with BroadCast */
void iSUBbc(VectorUnit *vu, u32 instr) {
    const auto fd = getD(instr);
    const auto fs = getS(instr);
    const auto ft = getT(instr);

    const auto dest = getDest(instr);

    const auto bc = instr & 3;

    const auto t = vu->getVF_F32(ft, bc);

    if (doDisasm) {
        std::printf("[VU%d       ] SUB%s%s VF%u, VF%u, VF%u\n", vu->vuID, bcStr[bc], destStr[dest], fd, fs, ft);
    }

    for (int i = 0; i < 4; i++) {
        if (dest & (1 << (3 - i))) vu->setVF(fd, i, vu->getVF_F32(fs, i) - t);
    }
}

/* WAIT Q */
void iWAITQ(VectorUnit *vu) {
    if (doDisasm) {
        std::printf("[VU%d       ] WAITQ\n", vu->vuID);
    }
}

/* Executes a COP2 instruction (VU0 only) */
void executeMacro(VectorUnit *vu, u32 instr) {
    assert(!vu->vuID);

    if ((instr & 0x3C) == 0x3C) {
        const auto opcode = ((instr >> 4) & 0x7C) | (instr & 3);

        switch (opcode) {
            case SPECIAL2Opcode::VMADDABC + 0:
            case SPECIAL2Opcode::VMADDABC + 1:
            case SPECIAL2Opcode::VMADDABC + 2:
            case SPECIAL2Opcode::VMADDABC + 3:
                iMADDAbc(vu, instr);
                break;
            case SPECIAL2Opcode::VFTOI4     : iFTOI4(vu, instr); break;
            case SPECIAL2Opcode::VMULABC + 0:
            case SPECIAL2Opcode::VMULABC + 1:
            case SPECIAL2Opcode::VMULABC + 2:
            case SPECIAL2Opcode::VMULABC + 3:
                iMULAbc(vu, instr);
                break;
            case SPECIAL2Opcode::VOPMULA: iOPMULA(vu, instr); break;
            case SPECIAL2Opcode::VNOP   : iNOP(vu); break;
            case SPECIAL2Opcode::VMOVE  : iMOVE(vu, instr); break;
            case SPECIAL2Opcode::VMR32  : iMR32(vu, instr); break;
            case SPECIAL2Opcode::VSQI   : iSQI(vu, instr); break;
            case SPECIAL2Opcode::VDIV   : iDIV(vu, instr); break;
            case SPECIAL2Opcode::VSQRT  : iSQRT(vu, instr); break;
            case SPECIAL2Opcode::VWAITQ : iWAITQ(vu); break;
            case SPECIAL2Opcode::VISWR  : iISWR(vu, instr); break;
            default:
                std::printf("[VU%d       ] Unhandled SPECIAL2 macro instruction 0x%02X (0x%08X)\n", vu->vuID, opcode, instr);

                exit(0);
        }
    } else {
        const auto opcode = instr & 0x3F;

        switch (opcode) {
            case SPECIAL1Opcode::VADDBC + 0:
            case SPECIAL1Opcode::VADDBC + 1:
            case SPECIAL1Opcode::VADDBC + 2:
            case SPECIAL1Opcode::VADDBC + 3:
                iADDbc(vu, instr);
                break;
            case SPECIAL1Opcode::VSUBBC + 0:
            case SPECIAL1Opcode::VSUBBC + 1:
            case SPECIAL1Opcode::VSUBBC + 2:
            case SPECIAL1Opcode::VSUBBC + 3:
                iSUBbc(vu, instr);
                break;
            case SPECIAL1Opcode::VMADDBC + 0:
            case SPECIAL1Opcode::VMADDBC + 1:
            case SPECIAL1Opcode::VMADDBC + 2:
            case SPECIAL1Opcode::VMADDBC + 3:
                iMADDbc(vu, instr);
                break;
            case SPECIAL1Opcode::VMULBC + 0:
            case SPECIAL1Opcode::VMULBC + 1:
            case SPECIAL1Opcode::VMULBC + 2:
            case SPECIAL1Opcode::VMULBC + 3:
                iMULbc(vu, instr);
                break;
            case SPECIAL1Opcode::VMULQ  : iMULQ(vu, instr); break;
            case SPECIAL1Opcode::VADDQ  : iADDQ(vu, instr); break;
            case SPECIAL1Opcode::VADD   : iADD(vu, instr); break;
            case SPECIAL1Opcode::VMUL   : iMUL(vu, instr); break;
            case SPECIAL1Opcode::VSUB   : iSUB(vu, instr); break;
            case SPECIAL1Opcode::VOPMSUB: iOPMSUB(vu, instr); break;
            case SPECIAL1Opcode::VIADD  : iIADD(vu, instr); break;
            default:
                std::printf("[VU%d       ] Unhandled SPECIAL1 macro instruction 0x%02X (0x%08X)\n", vu->vuID, opcode, instr);

                exit(0);
        }
    }
}

}
