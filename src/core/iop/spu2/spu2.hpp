/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::iop::spu2 {

u16 read(u32 addr);
u16 readPS1(u32 addr);

void write(u32 addr, u16 data);
void writePS1(u32 addr, u16 data);

void transferEnd(int coreID);

}
