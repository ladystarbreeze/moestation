/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../common/types.hpp"

namespace ps2::gs {
    void init();
    void initQ();

    u64 readPriv(u32 addr);

    void writePriv(u32 addr, u64 data);

    void write(u8 addr, u64 data);
    void writePACKED(u8 addr, const u128 &data);
    
    void writeHWREG(u64 data);
}
