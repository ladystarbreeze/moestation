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
    MSCOM = 0x1000F200,
    MSFLG = 0x1000F220,
    CTRL  = 0x1000F240,
    BD6   = 0x1000F260,
};

u32 read(u32 addr) {
    switch (addr) {
        default:
            std::printf("[SIF       ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write(u32 addr, u32 data) {
    switch (addr) {
        case SIFReg::MSCOM:
            std::printf("[SIF       ] 32-bit write @ MSCOM = 0x%08X\n", data);
            break;
        case SIFReg::MSFLG:
            std::printf("[SIF       ] 32-bit write @ MSFLG = 0x%08X\n", data);
            break;
        case SIFReg::CTRL:
            std::printf("[SIF       ] 32-bit write @ CTRL = 0x%08X\n", data);
            break;
        case SIFReg::BD6:
            std::printf("[SIF       ] 32-bit write @ BD6 = 0x%08X\n", data);
            break;
        default:
            std::printf("[SIF       ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

}
