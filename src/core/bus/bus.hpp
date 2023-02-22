/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../common/types.hpp"

namespace ps2::bus {

void init(const char *biosPath);

u8   read8(u32 addr);
u16  read16(u32 addr);
u32  read32(u32 addr);
u64  read64(u32 addr);
u128 read128(u32 addr);

void write8(u32 addr, u8 data);
void write16(u32 addr, u16 data);
void write32(u32 addr, u32 data);
void write64(u32 addr, u64 data);
void write128(u32 addr, const u128 &data);

}
