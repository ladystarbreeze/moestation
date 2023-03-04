/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::iop::dmac {

/* IOP DMA channels */
enum class Channel {
    MDECIN,
    MDECOUT,
    SIF2,
    CDVD,
    SPU1,
    PIO,
    OTC,
    SPU2,
    DEV9,
    SIF0,
    SIF1,
    SIO2IN,
    SIO2OUT,
    Unknown,
};

void init();

u32 read32(u32 addr);

void write16(u32 addr, u16 data);
void write32(u32 addr, u32 data);

void setDRQ(Channel chn, bool drq);

}
