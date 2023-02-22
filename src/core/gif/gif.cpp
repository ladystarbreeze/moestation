/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "gif.hpp"

#include <cassert>
#include <cstdio>

/* GIF registers */
enum GIFReg {
    CTRL = 0x10003000,
    STAT = 0x10003020,
};

namespace ps2::gif {

/* Returns a GIF register */
u32 read(u32 addr) {
    u32 data;

    switch (addr) {
        case GIFReg::STAT:
            std::printf("[GIF       ] Read @ GIF_STAT\n");
            return 0;
        default:
            std::printf("[GIF       ] Unhandled read @ 0x%08X\n", addr);

            exit(0);
    }

    return data;
}

/* Writes a GIF register */
void write(u32 addr, u32 data) {
    switch (addr) {
        case GIFReg::CTRL:
            std::printf("[GIF       ] Write @ GIF_CTRL = 0x%08X\n", data);

            if (data & 1) std::printf("[GIF       ] GIF reset\n");
            break;
        default:
            std::printf("[GIF       ] Unhandled write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

}
