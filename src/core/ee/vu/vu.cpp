/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "vu.hpp"

#include <cassert>
#include <cstdio>

/* --- VU registers --- */

/* COP2 control registers */
enum class ControlReg {
    FBRST = 28,
};

namespace ps2::ee::vu {

VectorUnit::VectorUnit(int vuID, VectorUnit *otherVU) {
    this->vuID = vuID;
    this->otherVU = otherVU;
}

void VectorUnit::reset() {
    std::printf("[VU%d       ] Reset\n", vuID);
}

void VectorUnit::forceBreak() {
    std::printf("[VU%d       ] Force break\n", vuID);
}

/* Returns a COP2 control register (VU0 only) */
u32 VectorUnit::getControl(u32 idx) {
    assert(!vuID);

    if (idx < 16) return vi[idx];

    switch (idx) {
        case static_cast<u32>(ControlReg::FBRST):
            std::printf("[VU%d       ] Read @ FBRST\n", vuID);
            return 0;
        default:
            std::printf("[VU%d       ] Unhandled control read @ %u\n", vuID, idx);

            exit(0);
    }
}

/* Writes a COP2 control register (VU0 only) */
void VectorUnit::setControl(u32 idx, u32 data) {
    assert(!vuID);

    if (idx < 16) {
        vi[idx] = data;

        return;
    }

    switch (idx) {
        case static_cast<u32>(ControlReg::FBRST):
            std::printf("[VU%d       ] Write @ FBRST = 0x%08X\n", vuID, data);

            if (data & (1 << 0)) forceBreak();
            if (data & (1 << 1)) reset();
            if (data & (1 << 8)) otherVU->forceBreak();
            if (data & (1 << 9)) otherVU->reset();
            break;
        default:
            std::printf("[VU%d       ] Unhandled control write @ %u = 0x%08X\n", vuID, idx, data);

            exit(0);
    }
}

}
