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
#include "ee/vif/vif.hpp"
#include "gs/gs.hpp"
#include "../common/types.hpp"

namespace ps2 {

using VectorInterface = ps2::ee::vif::VectorInterface;

/* --- moestation constants --- */

constexpr i64 EE_CYCLES = 16;

VectorInterface vif[2] = {VectorInterface(0, ps2::ee::cpu::getVU(0)), VectorInterface(1, ps2::ee::cpu::getVU(1))};

void init(const char *biosPath, const char *execPath) {
    std::printf("BIOS path: %s\nExec path: %s\n", biosPath, execPath);

    scheduler::init();

    bus::init(biosPath, &vif[0], &vif[1]);

    ee::cpu::init();
    ee::timer::init();
    
    gs::init();
}

void run() {
    while (true) {
        ee::cpu::step(EE_CYCLES);
        ee::timer::step(EE_CYCLES >> 1);

        scheduler::processEvents(EE_CYCLES);
    }
}

}
