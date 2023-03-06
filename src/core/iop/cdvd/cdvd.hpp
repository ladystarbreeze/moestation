/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::iop::cdvd {

void init(const char *path);

u8  read(u32 addr);
u32 readDMAC();

void write(u32 addr, u8 data);

void getExecPath(char *path);

i64 getSectorSize();

}
