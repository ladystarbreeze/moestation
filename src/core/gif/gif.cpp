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
};

namespace ps2::gif {

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
