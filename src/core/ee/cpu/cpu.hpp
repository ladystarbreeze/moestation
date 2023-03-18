/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../vu/vu.hpp"
#include "../../../common/types.hpp"

using VectorUnit = ps2::ee::vu::VectorUnit;

namespace ps2::ee::cpu {

void init();
void step(i64 c);

u128 readSPRAM128(u32 addr);

void doInterrupt();

VectorUnit *getVU(int vuID);

}
