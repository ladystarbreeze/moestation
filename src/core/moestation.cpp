/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "moestation.hpp"

#include <cstdio>
#include <cstring>

#include <ctype.h>

#include "scheduler.hpp"
#include "bus/bus.hpp"
#include "ee/cpu/cpu.hpp"
#include "ee/dmac/dmac.hpp"
#include "ee/timer/timer.hpp"
#include "ee/vif/vif.hpp"
#include "gs/gs.hpp"
#include "iop/iop.hpp"
#include "iop/cdvd/cdvd.hpp"
#include "iop/dmac/dmac.hpp"
#include "iop/timer/timer.hpp"
#include "../common/types.hpp"

namespace ps2 {

using VectorInterface = ee::vif::VectorInterface;

/* --- moestation constants --- */

constexpr i64 EE_CYCLES = 16;

VectorInterface vif[2] = {VectorInterface(0, ee::cpu::getVU(0)), VectorInterface(1, ee::cpu::getVU(1))};

char execPath[256];

void init(const char *biosPath, const char *path) {
    std::printf("BIOS path: \"%s\"\nExec path: \"%s\"\n", biosPath, path);

    std::strncpy(execPath, path, 256);

    scheduler::init();

    bus::init(biosPath, &vif[0], &vif[1]);

    ee::cpu::init();
    ee::dmac::init();
    ee::timer::init();
    
    gs::init();

    iop::init();
    iop::cdvd::init(execPath);
    iop::dmac::init();
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

/* Fast boots an ISO or ELF */
void fastBoot() {
    std::printf("[moestation] Fast booting \"%s\"...\n", execPath);

    /* Figure out the file type */
    char *ext = std::strrchr(execPath, '.');

    if (!ext) {
        std::printf("[moestation] No file extension found\n");

        exit(0);
    }

    if (std::strlen(ext) != 4) {
        std::printf("[moestation] Invalid file extension %s\n", ext);

        exit(0);
    }

    /* Convert to lowercase */
    for (int i = 1; i < 4; i++) {
        ext[i] = tolower(ext[i]);
    }

    if (std::strncmp(ext, ".iso", 4) == 0) {
        std::printf("[moestation] Loading ISO...\n");

        /* Get executable path from the ISO and replace it with the OSDSYS string in memory */
        char dvdPath[23] = "cdrom0:\\\\XXXX_000.00;1";

        iop::cdvd::getExecPath(dvdPath);

        bus::setPathEELOAD(dvdPath);
    } else if (std::strncmp(ext, ".elf", 4) == 0) {
        std::printf("[moestation] Loading ELF...\n");

        assert(false);
    } else {
        std::printf("[moestation] Invalid file extension %s\n", ext);

        exit(0);
    }
}

}
