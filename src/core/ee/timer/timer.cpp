/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "timer.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

/* EE timer registers */

enum TimerReg {
    COUNT = 0x10000000,
    MODE  = 0x10000010,
    COMP  = 0x10000020,
    HOLD  = 0x10000030,
};

/* T_MODE register */
struct Mode {
    u8   clks; // Clock source
    bool gate; // Gate enable
    bool gats; // Gate source
    u8   gatm; // Gate mode
    bool zret; // Zero return
    bool cue;  // Count up enable
    bool cmpe; // Compare enable
    bool ovfe; // Overflow enable
    bool equf; // Compare flag
    bool ovff; // Overflow flag
};

/* EE timer */
struct Timer {
    Mode mode; // T_MODE

    u32 count; // T_COUNT
    u16 comp;  // T_COMP
    u16 hold;  // T_HOLD

    /* Prescaler */
    u16 subcount;
    u16 prescaler;
};

Timer timers[4];

namespace ps2::ee::timer {

void init() {
    memset(&timers, 0, 4 * sizeof(Timer));

    timers[0].prescaler = 1;
    timers[1].prescaler = 1;
    timers[2].prescaler = 1;
    timers[3].prescaler = 1;

    std::printf("[Timer::EE ] Init OK\n");
}

u32 read32(u32 addr) {
    // Get channel ID
    const auto chn = (addr >> 11) & 3;

    auto &timer = timers[chn];

    switch (addr & ~0x1800) {
        case TimerReg::COUNT:
            std::printf("[Timer::EE ] 32-bit read @ T%u_COUNT\n", chn);
            return timer.count;
        default:
            std::printf("[Timer::EE ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write32(u32 addr, u32 data) {
    // Get channel ID
    const auto chn = (addr >> 11) & 3;

    auto &timer = timers[chn];

    switch (addr & ~0x1800) {
        case TimerReg::MODE:
            {
                auto &mode = timer.mode;

                std::printf("[Timer::EE ] 32-bit write @ T%u_MODE = 0x%08X\n", chn, data);

                mode.clks = data & 3;
                mode.gate = data & (1 << 2);
                mode.gats = data & (1 << 3);
                mode.gatm = (data >> 4) & 3;
                mode.zret = data & (1 << 6);
                mode.cue  = data & (1 << 7);
                mode.cmpe = data & (1 << 8);
                mode.ovfe = data & (1 << 9);

                if (data & (1 << 10)) mode.equf = false;
                if (data & (1 << 11)) mode.ovff = false;

                // Set prescaler
                switch (mode.clks) {
                    case 0: timer.prescaler = 1; break;
                    case 1: timer.prescaler = 16; break;
                    case 2: timer.prescaler = 256; break;
                    default: break;
                }

                timer.subcount = 0;
            }
            break;
        default:
            std::printf("[Timer::EE ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

/* Steps timers in HBLANK mode */
void stepHBLANK() {
    for (int i = 0; i < 4; i++) {
        auto &timer = timers[i];

        if (!timer.mode.cue || (timer.mode.clks != 3)) continue;

        timer.count++;

        if (timer.count == timer.comp) {
            if (timer.mode.cmpe && !timer.mode.equf) {
                // Checking EQUF is necessary because timer IRQs are edge-triggered
                timer.mode.equf = true;

                assert(false);
            }

            if (timer.mode.zret) timer.count = 0;
        } else if (timer.count & (1 << 16)) {
            if (timer.mode.ovfe && !timer.mode.ovff) {
                // Checking OVFF is necessary because timer IRQs are edge-triggered
                timer.mode.ovff = true;

                assert(false);
            }
        }
    }
}

}
