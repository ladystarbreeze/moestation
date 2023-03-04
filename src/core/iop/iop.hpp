/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../common/types.hpp"

namespace ps2::iop {

void init();
void step(i64 c);

void doInterrupt();

}
