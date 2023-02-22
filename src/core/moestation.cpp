/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "moestation.hpp"

#include <cstdio>

#include "scheduler.hpp"
#include "bus/bus.hpp"
#include "ee/cpu/cpu.hpp"
#include "ee/timer/timer.hpp"
#include "gs/gs.hpp"
#include "../common/types.hpp"

/* --- moestation constants --- */

constexpr i64 EE_CYCLES = 16;

namespace ps2 {

void init(const char *biosPath, const char *execPath) {
    std::printf("BIOS path: %s\nExec path: %s\n", biosPath, execPath);

    scheduler::init();

    bus::init(biosPath);

    ee::cpu::init();
    ee::timer::init();
    
    gs::init();
}

void run() {
    while (true) {
        ee::cpu::step(EE_CYCLES);

        scheduler::processEvents(EE_CYCLES);
    }
}

}
