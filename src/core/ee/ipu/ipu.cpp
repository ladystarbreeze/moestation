/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "ipu.hpp"

#include <cassert>
#include <cstdio>

/* IPU commands */
enum Command {
    BCLR  = 0x0,
    SETIQ = 0x5,
    SETTH = 0x9,
};

/* --- IPU registers --- */

enum class IPUReg {
    CMD  = 0x10002000,
    CTRL = 0x10002010,
};

/* Sets up an IPU command */
void doCmd(u32 data) {
    const auto cmd = data >> 28;

    switch (cmd) {
        case Command::BCLR:
            std::printf("[IPU       ] BCLR; BP = 0x%02X\n", data & 0xFF);
            break;
        case Command::SETIQ:
            std::printf("[IPU       ] SETIQ; IQM = %u, FB = 0x%02X\n", (data >> 27) & 1, data & 0x1F);
            break;
        case Command::SETIQ + 1:
            std::printf("[IPU       ] SETIQ\n");
            break;
        case Command::SETTH:
            std::printf("[IPU       ] SETTH; TH1 = 0x%02X, TH0 = 0x%02X\n", (data >> 16) & 0xFF, data & 0xFF);
            break;
        default:
            std::printf("[IPU       ] Unhandled command 0x%X\n", cmd);

            exit(0);
    }
}

namespace ps2::ee::ipu {

u32 read(u32 addr) {
    switch (addr) {
        case static_cast<u32>(IPUReg::CTRL):
            std::printf("[IPU       ] 32-bit read @ CTRL\n");
            return 0;
        default:
            std::printf("[IPU       ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write(u32 addr, u32 data) {
    switch (addr) {
        case static_cast<u32>(IPUReg::CMD):
            std::printf("[IPU       ] 32-bit write @ CMD = 0x%08X\n", data);

            doCmd(data);
            break;
        case static_cast<u32>(IPUReg::CTRL):
            std::printf("[IPU       ] 32-bit write @ CTRL = 0x%08X\n", data);

            if (data & (1 << 30)) std::printf("[IPU       ] Reset\n");
            break;
        default:
            std::printf("[IPU       ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

}
