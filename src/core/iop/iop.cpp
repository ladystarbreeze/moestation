/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "iop.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

namespace ps2::iop {

/* --- IOP constants --- */

constexpr u32 RESET_VECTOR = 0xBFC00000;

constexpr auto doDisasm = false;

/* --- IOP registers --- */

u32 regs[34];

void init() {
    std::memset(&regs, 0, 34 * sizeof(u32));

    // Set program counter to reset vector
    //setPC(RESET_VECTOR);

    // Initialize coprocessors
    //cop0::init();

    std::printf("[IOP       ] Init OK\n");
}

}
