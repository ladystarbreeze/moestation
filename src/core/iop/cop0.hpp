/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../common/types.hpp"

namespace ps2::iop::cop0 {

/* Exception codes */
enum Exception {
    SystemCall = 0x8,
};

static const char *eNames[32] = { 
    "INT", "MOD", "TLBL", "TLBS", "AdEL", "AdES", "IBE", "DBE", "Syscall", "BP", "RI", "CpU", "Ov",
};

void init();

u32 get(u32 idx);

void set(u32 idx, u32 data);

void enterException(Exception e);
void leaveException();

bool isBEV();
bool isCacheIsolated();

void setBD(bool bd);
void setEPC(u32 pc);

}