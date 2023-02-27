/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::cpu::cop0 {

/* --- EE exceptions --- */

enum Exception {
    Interrupt  = 0x0,
    SystemCall = 0x8,
};

static const char *eNames[32] = { 
    "INT", "MOD", "TLBL", "TLBS", "AdEL", "AdES", "IBE", "DBE", "Syscall", "BP", "RI", "CpU", "Ov",
};

void init();
void incrementCount(i64 c);

u32 get32(u32 idx);

void set32(u32 idx, u32 data);

bool isBEV();
bool isEDI();
bool isERL();
bool isEXL();

void setBD(bool bd);
void setEIE(bool eie);
void setERL(bool erl);
void setEXL(bool exl);

u32 getEPC();
u32 getErrorEPC();

void setEPC(u32 pc);

}
