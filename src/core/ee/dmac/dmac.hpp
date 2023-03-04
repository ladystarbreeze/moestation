/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::dmac {

/* DMA channels */
enum class Channel {
    VIF0,    // Vector Interface 0
    VIF1,    // Vector Interface 1
    PATH3,   // Graphics Interface (PATH3)
    IPUFROM, // From Image Processing Unit
    IPUTO,   // To Image Processing Unit
    SIF0,    // Subsystem Interface (from IOP)
    SIF1,    // Subsystem Interface (to IOP)
    SIF2,    // Subsystem Interface
    SPRFROM, // From scratchpad
    SPRTO,   // To scratchpad
};

void init();

u32 read(u32 addr);
u32 readEnable();

void write(u32 addr, u32 data);
void writeEnable(u32 data);

void setDRQ(Channel chn, bool drq);

}
