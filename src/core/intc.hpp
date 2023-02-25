/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../common/types.hpp"

namespace ps2::intc {

u16 readMask();
u16 readStat();

u32 readMaskIOP();
u32 readStatIOP();
u32 readCtrlIOP();

void writeMask(u16 data);
void writeStat(u16 data);

void writeMaskIOP(u32 data);
void writeStatIOP(u32 data);
void writeCtrlIOP(u32 data);

}
