/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::cpu::cop0 {

void init();
void incrementCount(i64 c);

u32 get32(u32 idx);

void set32(u32 idx, u32 data);

bool isEDI();
bool isERL();
bool isEXL();

void setEIE(bool eie);
void setERL(bool erl);
void setEXL(bool exl);

u32 getEPC();
u32 getErrorEPC();

}
