/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "timer.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

#include "../../intc.hpp"

namespace ps2::iop::timer {

using IOPInterrupt = intc::IOPInterrupt;

/* --- IOP timer registers --- */

enum TimerReg {
    COUNT = 0x1F801100,
    MODE  = 0x1F801104,
    COMP  = 0x1F801108,
};

/* Timer mode register */
struct Mode {
    bool gate; // GATE enable
    u8   gats; // GATe Select
    bool zret; // Zero RETurn
    bool cmpe; // CoMPare Enable
    bool ovfe; // OVerFlow Enable
    bool rept; // REPeaT interrupt
    bool levl; // LEVL
    bool clks; // CLocK Select
    bool pre2; // Prescaler (timer 2)
    bool intf; // INTerrupt Flag
    bool equf; // EQUal Flag
    bool ovff; // OVerFlow Flag
    u8   pre4; // Prescaler (timer 4/5)
};

/* IOP timer */
struct Timer {
    Mode mode; // T_MODE

    u64 count; // T_COUNT
    u32 comp;  // T_COMP

    // Prescaler
    u16 subcount;
    u16 prescaler;
};

Timer timers[6];

/* Returns timer ID from address */
int getTimer(u32 addr) { 
    switch ((addr >> 4) & 0xFF) {
        case 0x10: return 0;
        case 0x11: return 1;
        case 0x12: return 2;
        case 0x48: return 3;
        case 0x49: return 4;
        case 0x4A: return 5;
        default:
            std::printf("[Timer:IOP  ] Invalid timer\n");

            exit(0);
    }
}

void sendInterrupt(int tmID) {
    auto &mode = timers[tmID].mode;

    if (mode.intf) {
        if (tmID < 3) {
            intc::sendInterruptIOP(static_cast<IOPInterrupt>(tmID + 4));
        } else {
            intc::sendInterruptIOP(static_cast<IOPInterrupt>(tmID + 11));
        }
    }

    if (mode.rept && mode.levl) {
        mode.intf = !mode.intf;
    } else {
        mode.intf = false;
    }
}

void init() {
    memset(&timers, 0, 4 * sizeof(Timer));

    for (auto &i : timers) i.prescaler = 1;

    std::printf("[Timer:IOP ] Init OK\n");
}

u16 read16(u32 addr) {
    u16 data;

    // Get channel ID
    const auto chn = getTimer(addr);

    auto &timer = timers[chn];

    switch ((addr & ~0xFF0) | (1 << 8)) {
        case TimerReg::MODE:
            {
                std::printf("[Timer:IOP ] 16-bit read @ T%d_MODE\n", chn);
                
                auto &mode = timer.mode;

                data  = mode.gate;
                data |= mode.gats << 1;
                data |= mode.zret << 3;
                data |= mode.cmpe << 4;
                data |= mode.ovfe << 5;
                data |= mode.rept << 6;
                data |= mode.levl << 7;
                data |= mode.clks << 8;
                data |= mode.pre2 << 9;
                data |= mode.intf << 10;
                data |= mode.equf << 11;
                data |= mode.ovff << 12;
                data |= mode.pre4 << 13;

                /* Clear interrupt flags */

                mode.equf = false;
                mode.ovff = false;
            }
            break;
        default:
            std::printf("[Timer:IOP ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }

    return data;
}

u32 read32(u32 addr) {
    // Get channel ID
    const auto chn = getTimer(addr);

    auto &timer = timers[chn];

    switch ((addr & ~0xFF0) | (1 << 8)) {
        case TimerReg::COUNT:
            std::printf("[Timer:IOP ] 32-bit read @ T%d_COUNT\n", chn);
            return timer.count;
        default:
            std::printf("[Timer:IOP ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write16(u32 addr, u16 data) {
    // Get channel ID
    const auto chn = getTimer(addr);

    auto &timer = timers[chn];

    switch ((addr & ~0xFF0) | (1 << 8)) {
        case TimerReg::MODE:
            {
                auto &mode = timer.mode;

                std::printf("[Timer:IOP ] 16-bit write @ T%d_MODE = 0x%04X\n", chn, data);

                mode.gate = data & 1;
                mode.gats = (data >> 1) & 3;
                mode.zret = data & (1 << 3);
                mode.cmpe = data & (1 << 4);
                mode.ovfe = data & (1 << 5);
                mode.rept = data & (1 << 6);
                mode.levl = data & (1 << 7);
                mode.clks = data & (1 << 8);
                mode.pre2 = data & (1 << 9);
                mode.pre4 = (data >> 13) & 3;

                mode.intf = true; // Always reset to 1

                if (mode.gate) {
                    std::printf("[Timer::IOP ] Unhandled timer gate\n");

                    exit(0);
                }

                if (mode.clks) {
                    std::printf("[Timer::EE  ] Unhandled clock source\n");

                    exit(0);
                }

                // Set prescaler
                if ((chn == 2) && mode.pre2) {
                    timer.prescaler = 8;
                } else if ((chn >= 4)) {
                    switch (mode.pre4) {
                        case 0: timer.prescaler = 1;
                        case 1: timer.prescaler = 8;
                        case 2: timer.prescaler = 16;
                        case 3: timer.prescaler = 256;
                    }
                } else {
                    timer.prescaler = 1;
                }

                timer.subcount = 0;
                timer.count = 0;    // Always cleared
            }
            break;
        default:
            std::printf("[Timer:IOP ] Unhandled 16-bit write @ 0x%08X = 0x%04X\n", addr, data);

            exit(0);
    }
}

void write32(u32 addr, u32 data) {
    // Get channel ID
    const auto chn = getTimer(addr);

    auto &timer = timers[chn];

    switch ((addr & ~0xFF0) | (1 << 8)) {
        case TimerReg::COUNT:
            std::printf("[Timer:IOP ] 32-bit write @ T%d_COUNT = 0x%08X\n", chn, data);

            timer.count = data;

            if (chn < 4) timer.count &= 0xFFFF;
            break;
        case TimerReg::COMP:
            std::printf("[Timer:IOP ] 32-bit write @ T%d_COMP = 0x%08X\n", chn, data);

            timer.comp = data;

            if (chn < 4) timer.comp &= 0xFFFF;

            if (!timer.mode.levl) timer.mode.intf = true;
            break;
        default:
            std::printf("[Timer:IOP ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

/* Steps timers */
void step(i64 c) {
    for (int i = 0; i < 6; i++) {
        auto &timer = timers[i];

        /* Timers 0, 1 and 3 have a different clock source if CLKS is set */
        if (timer.mode.clks && ((i == 0) || (i == 1) || (i == 3))) continue;

        timer.subcount += c;

        while (timer.subcount > timer.prescaler) {
            timer.count++;

            if (timer.count & (1 << (16 + 2 * (i > 2)))) { // 1 << 16 for timer 0-2, 1 << 32 for timer 3-5
                if (timer.mode.ovfe && !timer.mode.ovff) {
                    // Checking OVFF is necessary because timer IRQs are edge-triggered
                    timer.mode.ovff = true;

                    sendInterrupt(i);
                }
            }

            if (i < 3) { timer.count &= 0xFFFF; } else { timer.count &= 0xFFFFFFFF; }

            if (timer.count == timer.comp) {
                if (timer.mode.cmpe && !timer.mode.equf) {
                    // Checking EQUF is necessary because timer IRQs are edge-triggered
                    timer.mode.equf = true;

                    sendInterrupt(i);
                }

                if (timer.mode.zret) timer.count = 0;
            }

            timer.subcount -= timer.prescaler;
        }
    }
}

}
