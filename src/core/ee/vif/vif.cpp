/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "vif.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::ee::vif {

/* --- VIF registers --- */

enum VIFReg {
    STAT  = 0x10003800,
    FBRST = 0x10003810,
    ERR   = 0x10003820,
    MARK  = 0x10003830,
};

VectorInterface::VectorInterface(int vifID, VectorUnit *vu) {
    this->vifID = vifID;
    this->vu = vu;
}

void VectorInterface::write(u32 addr, u32 data) {
    switch (addr & ~(1 << 10)) {
        case VIFReg::STAT:
            std::printf("[VIF%d      ] 32-bit write @ STAT = 0x%08X\n", vifID, data);
            break;
        case VIFReg::FBRST:
            std::printf("[VIF%d      ] 32-bit write @ FBRST = 0x%08X\n", vifID, data);

            if (data & (1 << 0)) std::printf("[VIF%d      ] Reset\n", vifID);
            if (data & (1 << 1)) std::printf("[VIF%d      ] Force break\n", vifID);
            if (data & (1 << 2)) std::printf("[VIF%d      ] Stop\n", vifID);
            if (data & (1 << 3)) std::printf("[VIF%d      ] Stall cancel\n", vifID);
            break;
        case VIFReg::ERR:
            std::printf("[VIF%d      ] 32-bit write @ ERR = 0x%08X\n", vifID, data);
            break;
        case VIFReg::MARK:
            std::printf("[VIF%d      ] 32-bit write @ MARK = 0x%08X\n", vifID, data);
            break;
        default:
            std::printf("[VIF%d      ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", vifID, addr, data);

            exit(0);
    }
}

}
