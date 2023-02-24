/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "gs.hpp"

#include <cassert>
#include <cstdio>

#include "../scheduler.hpp"
#include "../ee/timer/timer.hpp"

namespace ps2::gs {

/* --- GS constants --- */

constexpr i64 CYCLES_PER_SCANLINE = 2 * 9370; // NTSC, converted to EE clock
//constexpr i64 SCANLINES_PER_VDRAW = 240;
//constexpr i64 SCANLINES_PER_FRAME = 262;

/* --- GS privileged registers --- */
enum PrivReg {
    SMODE1 = 0x12000010,
    SMODE2 = 0x12000020,
    SRFSH  = 0x12000030,
    SYNCH1 = 0x12000040,
    SYNCH2 = 0x12000050,
    SYNCV  = 0x12000060,
    CSR    = 0x12001000,
};

/* GS scheduler event IDs */
u64 idHBLANK;

/* Handles HBLANK events */
void hblankEvent(i64 c) {
    ps2::ee::timer::stepHBLANK();
    
    ps2::scheduler::addEvent(idHBLANK, CYCLES_PER_SCANLINE + c);
}

/* Registers GS events */
void init() {
    idHBLANK = scheduler::registerEvent([](i64 c) { hblankEvent(c); });

    scheduler::addEvent(idHBLANK, CYCLES_PER_SCANLINE);
}

/* Writes a GS privileged register (64-bit) */
void writePriv64(u32 addr, u64 data) {
    switch (addr) {
        case PrivReg::SMODE1:
            std::printf("[GS        ] 64-bit write @ SMODE1 = 0x%016llX\n", data);
            break;
        case PrivReg::SMODE2:
            std::printf("[GS        ] 64-bit write @ SMODE2 = 0x%016llX\n", data);
            break;
        case PrivReg::SRFSH:
            std::printf("[GS        ] 64-bit write @ SRFSH = 0x%016llX\n", data);
            break;
        case PrivReg::SYNCH1:
            std::printf("[GS        ] 64-bit write @ SYNCH1 = 0x%016llX\n", data);
            break;
        case PrivReg::SYNCH2:
            std::printf("[GS        ] 64-bit write @ SYNCH2 = 0x%016llX\n", data);
            break;
        case PrivReg::SYNCV:
            std::printf("[GS        ] 64-bit write @ SYNCV = 0x%016llX\n", data);
            break;
        case PrivReg::CSR:
            std::printf("[GS        ] 64-bit write @ GS_CSR = 0x%016llX\n", data);
            break;
        default:
            std::printf("[GS        ] Unhandled 64-bit write @ 0x%08X = 0x%016llX\n", addr, data);

            exit(0);
    }
}

}
