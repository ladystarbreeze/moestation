/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../common/types.hpp"

namespace ps2::gs {
    void init();

    u64 readPriv64(u32 addr);

    void writePriv64(u32 addr, u64 data);
}
