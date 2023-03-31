/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::pgif {

u32 read(u32 addr);

u32 readGPUSTAT();

void write(u32 addr, u32 data);

void writeGP0(u32 data);
void writeGP1(u32 data);

}