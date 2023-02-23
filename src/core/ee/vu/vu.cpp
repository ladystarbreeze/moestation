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

const f32 vf0Data[4] = {0.0, 0.0, 0.0, 1.0};

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

/* Returns VF register element */
f32 VectorUnit::getVF(u32 idx, u32 e) {
    return vf[idx][e];
}

/* Returns an integer register */
u16 VectorUnit::getVI(u32 idx) {
    return vi[idx];
}

/* Writes VU mem (32-bit) */
void VectorUnit::writeData32(u32 addr, u32 data) {
    if (addr > 0x4000) { // VU1 registers are mapped to these addresses (VU0 only)
        assert(!vuID);

        if (addr < 0x4200) {
            const auto idx = (addr >> 4) & 0x1F;

            const auto e = (addr >> 2) & 3; // VF element

            return otherVU->setVF(idx, e, *(f32 *)&data);
        } else if (addr < 0x4300) {
            if ((addr >> 2) & 3) return; // VIs are mapped to 16-byte aligned addresses

            const auto idx = (addr >> 4) & 0xF;

            return otherVU->setVI(idx, data);
        } else if (addr < 0x4400) {
            if ((addr >> 2) & 3) return; // Control registers are mapped to 16-byte aligned addresses

            std::printf("[VU%d       ] 32-bit write @ 0x%04X = 0x%08X\n", vuID, addr, data);

            return;
        } else {
            std::printf("[VU%d       ] Unhandled 32-bit write @ 0x%04X = 0x%08X\n", vuID, addr, data);

            exit(0);
        }
    }

    std::printf("[VU%d       ] Unhandled 32-bit write @ 0x%04X = 0x%08X\n", vuID, addr, data);

    exit(0);
}

/* Writes a COP2 control register (VU0 only) */
void VectorUnit::setControl(u32 idx, u32 data) {
    assert(!vuID);

    if (idx < 16) {
        return setVI(idx, data);
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

/* Sets a VF register element */
void VectorUnit::setVF(u32 idx, u32 e, f32 data) {
    std::printf("[VU%d       ] VF%u.%s = %f\n", vuID, idx, elementStr[e], data);

    vf[idx][e] = data;

    vf[0][e] = vf0Data[e];
}

/* Sets a VI register */
void VectorUnit::setVI(u32 idx, u16 data) {
    std::printf("[VU%d       ] VI%u = 0x%04X\n", vuID, idx, data);

    vi[idx] = data;

    vi[0] = 0;
}

}
