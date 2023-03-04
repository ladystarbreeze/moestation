/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../common/types.hpp"

namespace ps2::sif {

u32  read(u32 addr);
u32  readIOP(u32 addr);
u128 readSIF0();
u32  readSIF1();

void write(u32 addr, u32 data);
void writeIOP(u32 addr, u32 data);
void writeSIF0(u32 data);
void writeSIF1(const u128 &data);

int getSIF0Size();
int getSIF1Size();

}
