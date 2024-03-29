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
#include "iop/cdrom/cdrom.hpp"
#include "iop/cdvd/cdvd.hpp"
#include "iop/dmac/dmac.hpp"
#include "iop/timer/timer.hpp"

#include <SDL2/SDL.h>

#undef main

namespace ps2 {

using VectorInterface = ee::vif::VectorInterface;

/* --- moestation constants --- */

/* SDL2 */
SDL_Renderer *renderer;
SDL_Window   *window;
SDL_Texture  *texture;

SDL_Event e;

VectorInterface vif[2] = {VectorInterface(0, ee::cpu::getVU(0)), VectorInterface(1, ee::cpu::getVU(1))};

char execPath[256];

bool isRunning = true, psxFastBoot = false;

/* Initializes SDL */
void initSDL() {
    SDL_Init(SDL_INIT_VIDEO);
    SDL_SetHint(SDL_HINT_RENDER_VSYNC, "1");

    SDL_CreateWindowAndRenderer(640, 480, 0, &window, &renderer);
    SDL_SetWindowSize(window, 640, 480);
    SDL_RenderSetLogicalSize(renderer, 640, 480);
    SDL_SetWindowResizable(window, SDL_FALSE);
    SDL_SetWindowTitle(window, "moestation");

    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_XBGR8888, SDL_TEXTUREACCESS_STREAMING, 640, 480);
}

void init(const char *biosPath, const char *path, const char *psxmode) {
    std::printf("BIOS path: \"%s\"\nExec path: \"%s\"\n", biosPath, path);

    if (psxmode && (std::strncmp(psxmode, "-PSXMODE", 8) == 0)) psxFastBoot = true;

    std::strncpy(execPath, path, 256);

    scheduler::init();

    bus::init(biosPath, &vif[0], &vif[1]);

    ee::cpu::init();
    ee::dmac::init();
    ee::timer::init();
    
    gs::init();

    iop::init();
    iop::dmac::init();
    iop::timer::init();

    iop::cdvd::init(execPath);
    iop::cdrom::init(execPath);

    scheduler::flush();

    initSDL();
}

void run() {
    while (isRunning) {
        const auto runCycles = scheduler::getRunCycles();

        scheduler::processEvents(runCycles);

        /* Step EE hardware */

        ee::cpu::step(runCycles);
        ee::timer::step(runCycles >> 1);

        /* Step IOP hardware */

        iop::step(runCycles >> 3);
        iop::timer::step(runCycles >> 3);

        scheduler::flush();
    }

    SDL_Quit();
}

void enterPS1Mode() {
    iop::enterPS1Mode();
    iop::dmac::enterPS1Mode();
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

    if ((std::strncmp(ext, ".iso", 4) == 0) || std::strncmp(ext, ".bin", 4) == 0) {
        std::printf("[moestation] Loading ISO...\n");

        if (psxFastBoot) {
            std::printf("[moestation] PSX fast boot\n");

            return bus::setPathEELOAD("rom0:PS1DRV");
        }

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

void update(const u8 *fb) {
    SDL_PollEvent(&e);

    switch (e.type) {
        case SDL_QUIT: isRunning = false; break;
        default: break;
    }

    SDL_UpdateTexture(texture, nullptr, fb, 4 * 640);
    SDL_RenderCopy(renderer, texture, nullptr, nullptr);
    SDL_RenderPresent(renderer);
}

}
