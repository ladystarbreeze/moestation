/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::iop::sio2 {

u32 read(u32 addr);
u8 readFIFO();

void write(u32 addr, u32 data);
void writeFIFO(u8 data);

u32 readDMAC();

void writeDMAC(u32 data);

}
