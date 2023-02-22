/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::cop0 {

void init();

u32 get32(u32 idx);

void set32(u32 idx, u32 data);

void incrementCount(i64 c);

}
