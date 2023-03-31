/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../common/types.hpp"

namespace ps2 {

void init(const char *biosPath, const char *execPath, const char *psxmode);
void run();

void fastBoot();

void update(const u8 *fb);

}
