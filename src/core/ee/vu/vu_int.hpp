/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "vu.hpp"
#include "../../../common/types.hpp"

namespace ps2::ee::vu::interpreter {

void executeMacro(VectorUnit *vu, u32 instr);

}
