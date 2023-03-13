/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "gs.hpp"

#include <cassert>
#include <cstdio>

#include "../intc.hpp"
#include "../scheduler.hpp"
#include "../ee/timer/timer.hpp"

namespace ps2::gs {

using Interrupt = intc::Interrupt;
using IOPInterrupt = intc::IOPInterrupt;

/* --- GS constants --- */

constexpr i64 CYCLES_PER_SCANLINE = 2 * 9370; // NTSC, converted to EE clock
constexpr i64 SCANLINES_PER_VDRAW = 240;
constexpr i64 SCANLINES_PER_FRAME = 262;

/* --- GS privileged registers --- */
enum PrivReg {
    PMODE    = 0x12000000,
    SMODE1   = 0x12000010,
    SMODE2   = 0x12000020,
    SRFSH    = 0x12000030,
    SYNCH1   = 0x12000040,
    SYNCH2   = 0x12000050,
    SYNCV    = 0x12000060,
    DISPFB2  = 0x12000090,
    DISPLAY2 = 0x120000A0,
    BGCOLOR  = 0x120000E0,
    CSR      = 0x12001000,
    IMR      = 0x12001010,
};

u64 csr;

i64 lineCounter = 0;

/* GS scheduler event IDs */
u64 idHBLANK;

/* Handles HBLANK events */
void hblankEvent(i64 c) {
    ee::timer::stepHBLANK();

    csr |= 1 << 2; // HBLANK

    ++lineCounter;

    if (lineCounter == SCANLINES_PER_VDRAW) {
        intc::sendInterrupt(Interrupt::VBLANKStart);
        intc::sendInterruptIOP(IOPInterrupt::VBLANKStart);

        csr |= 1 << 3;  // VBLANK
        csr ^= 1 << 13; // FIELD
    } else if (lineCounter == SCANLINES_PER_FRAME) {
        intc::sendInterrupt(Interrupt::VBLANKEnd);
        intc::sendInterruptIOP(IOPInterrupt::VBLANKEnd);

        lineCounter = 0;
    }
    
    scheduler::addEvent(idHBLANK, 0, CYCLES_PER_SCANLINE + c, false);
}

/* Registers GS events */
void init() {
    idHBLANK = scheduler::registerEvent([](int, i64 c) { hblankEvent(c); });

    scheduler::addEvent(idHBLANK, 0, CYCLES_PER_SCANLINE, true);
}

u64 readPriv64(u32 addr) {
    switch (addr) {
        case PrivReg::CSR:
            //std::printf("[GS        ] Unhandled 64-bit read @ CSR\n");
            return csr;
        default:
            std::printf("[GS        ] Unhandled 64-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

/* Writes a GS privileged register (64-bit) */
void writePriv64(u32 addr, u64 data) {
    switch (addr) {
        case PrivReg::PMODE:
            std::printf("[GS        ] 64-bit write @ PMODE = 0x%016llX\n", data);
            break;
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
        case PrivReg::DISPFB2:
            std::printf("[GS        ] 64-bit write @ DISPFB2 = 0x%016llX\n", data);
            break;
        case PrivReg::DISPLAY2:
            std::printf("[GS        ] 64-bit write @ DISPLAY2 = 0x%016llX\n", data);
            break;
        case PrivReg::BGCOLOR:
            std::printf("[GS        ] 64-bit write @ BGCOLOR = 0x%016llX\n", data);
            break;
        case PrivReg::CSR:
            std::printf("[GS        ] 64-bit write @ CSR = 0x%016llX\n", data);

            csr = data;
            break;
        case PrivReg::IMR:
            std::printf("[GS        ] 64-bit write @ IMR = 0x%016llX\n", data);
            break;
        default:
            std::printf("[GS        ] Unhandled 64-bit write @ 0x%08X = 0x%016llX\n", addr, data);

            exit(0);
    }
}

}
