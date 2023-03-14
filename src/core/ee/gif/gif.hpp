/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::gif {

u32 read(u32 addr);

void write(u32 addr, u32 data);

void writePATH3(const u128 &data);

}
