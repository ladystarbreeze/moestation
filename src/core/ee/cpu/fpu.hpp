/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::cpu::fpu {

f32 get(u32 idx);
u32 getControl(u32 idx);

void set(u32 idx, f32 data);
void setControl(u32 idx, u32 data);

bool getCPCOND();

void executeSingle(u32 instr);

}
