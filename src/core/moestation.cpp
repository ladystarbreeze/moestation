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
#include "iop/iop.hpp"
#include "iop/timer/timer.hpp"
#include "../common/types.hpp"

namespace ps2 {

using VectorInterface = ee::vif::VectorInterface;

/* --- moestation constants --- */

constexpr i64 EE_CYCLES = 32;

VectorInterface vif[2] = {VectorInterface(0, ee::cpu::getVU(0)), VectorInterface(1, ee::cpu::getVU(1))};

void init(const char *biosPath, const char *execPath) {
    std::printf("BIOS path: %s\nExec path: %s\n", biosPath, execPath);

    scheduler::init();

    bus::init(biosPath, &vif[0], &vif[1]);

    ee::cpu::init();
    ee::timer::init();
    
    gs::init();

    iop::init();
    iop::timer::init();
}

void run() {
    while (true) {
        /* Step EE hardware */

        ee::cpu::step(EE_CYCLES);
        ee::timer::step(EE_CYCLES >> 1);

        /* Step IOP hardware */

        iop::step(EE_CYCLES >> 3);
        iop::timer::step(EE_CYCLES >> 3);

        scheduler::processEvents(EE_CYCLES);
    }
}

}
