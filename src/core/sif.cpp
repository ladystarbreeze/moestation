/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "sif.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::sif {

/* --- SIF registers --- */

enum SIFReg {
    MSCOM = 0x00,
    SMCOM = 0x10,
    MSFLG = 0x20,
    SMFLG = 0x30,
    CTRL  = 0x40,
    BD6   = 0x60,
};

u32 mscom = 0, msflg = 0; // EE->IOP communication
u32 smcom = 0, smflg = 0; // IOP->EE communication

u32 bd6;

u32 read(u32 addr) {
    switch (addr & 0xFF) {
        case SIFReg::MSCOM:
            std::printf("[SIF:EE    ] 32-bit read @ MSCOM\n");
            return mscom;
        case SIFReg::SMCOM:
            std::printf("[SIF:EE    ] 32-bit read @ SMCOM\n");
            return smcom;
        case SIFReg::MSFLG:
            //std::printf("[SIF:EE    ] 32-bit read @ MSFLG\n");
            return msflg;
        case SIFReg::SMFLG:
            //std::printf("[SIF:EE    ] 32-bit read @ SMFLG\n");
            return smflg;
        default:
            std::printf("[SIF:EE    ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

u32 readIOP(u32 addr) {
    switch (addr & 0xFF) {
        case SIFReg::SMCOM:
            std::printf("[SIF:IOP   ] 32-bit read @ SMCOM\n");
            return smcom;
        case SIFReg::MSFLG:
            //std::printf("[SIF:IOP   ] 32-bit read @ MSFLG\n");
            return msflg;
        case SIFReg::SMFLG:
            //std::printf("[SIF:IOP   ] 32-bit read @ SMFLG\n");
            return smflg;
        case SIFReg::CTRL:
            std::printf("[SIF:IOP   ] 32-bit read @ CTRL\n");
            return 0xF0000101; // ??
        case SIFReg::BD6:
            std::printf("[SIF:IOP   ] 32-bit read @ BD6\n");
            return bd6;
        default:
            std::printf("[SIF:IOP   ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write(u32 addr, u32 data) {
    switch (addr & 0xFF) {
        case SIFReg::MSCOM:
            std::printf("[SIF:EE    ] 32-bit write @ MSCOM = 0x%08X\n", data);
            
            mscom = data;
            break;
        case SIFReg::MSFLG:
            std::printf("[SIF:EE    ] 32-bit write @ MSFLG = 0x%08X\n", data);

            msflg |= data;
            break;
        case SIFReg::SMFLG:
            std::printf("[SIF:EE    ] 32-bit write @ SMFLAG = 0x%08X\n", data);

            smflg &= ~data;
            break;
        case SIFReg::CTRL:
            std::printf("[SIF:EE    ] 32-bit write @ CTRL = 0x%08X\n", data);
            break;
        case SIFReg::BD6:
            std::printf("[SIF:EE    ] 32-bit write @ BD6 = 0x%08X\n", data);

            bd6 = data;
            break;
        default:
            std::printf("[SIF:EE    ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

void writeIOP(u32 addr, u32 data) {
    switch (addr & 0xFF) {
        case SIFReg::SMCOM:
            std::printf("[SIF:IOP   ] 32-bit write @ SMCOM = 0x%08X\n", data);

            smcom = data;
            break;
        case SIFReg::MSFLG:
            std::printf("[SIF:IOP   ] 32-bit write @ MSFLG = 0x%08X\n", data);

            msflg &= ~data;
            break;
        case SIFReg::SMFLG:
            std::printf("[SIF:IOP   ] 32-bit write @ SMFLG = 0x%08X\n", data);

            smflg |= data;
            break;
        case SIFReg::CTRL:
            std::printf("[SIF:IOP   ] 32-bit write @ CTRL = 0x%08X\n", data);
            break;
        default:
            std::printf("[SIF:IOP   ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

}
