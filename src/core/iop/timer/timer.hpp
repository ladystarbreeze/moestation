/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::iop::timer {

void init();

u16 read16(u32 addr);
u32 read32(u32 addr);

void write16(u32 addr, u16 data);
void write32(u32 addr, u32 data);

void step(i64 c);

}
