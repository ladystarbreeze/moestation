/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::timer {

void init();

u32 read32(u32 addr);

void write32(u32 addr, u32 data);

void stepHBLANK();

}
