/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../common/types.hpp"

namespace ps2::intc {

u16 readMask();
u16 readStat();

void writeMask(u16 data);
void writeStat(u16 data);

}