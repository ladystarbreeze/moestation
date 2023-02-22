/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include <functional>

#include "../common/types.hpp"

namespace ps2::scheduler {

void init();

u64 registerEvent(std::function<void(i64)> func);

void addEvent(u64 id, i64 cyclesUntilEvent);
void processEvents(i64 elapsedCycles);

}
