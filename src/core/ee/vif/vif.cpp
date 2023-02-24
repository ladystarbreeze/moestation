/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "vif.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::ee::vif {

VectorInterface::VectorInterface(int vifID, VectorUnit *vu) {
    this->vifID = vifID;
    this->vu = vu;
}

void VectorInterface::write(u32 addr, u32 data) {
    std::printf("[VIF%d      ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", vifID, addr, data);

    exit(0);
}

}
