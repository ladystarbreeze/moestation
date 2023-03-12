/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "sio2.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

#include "../dmac/dmac.hpp"

namespace ps2::iop::sio2 {

using Channel = dmac::Channel;

/* --- SIO2 registers --- */

enum SIO2Reg {
    SEND3   = 0x1F808200,
    SEND1   = 0x1F808240,
    FIFOIN  = 0x1F808260,
    FIFOOUT = 0x1F808264,
    CTRL    = 0x1F808268,
    RECV1   = 0x1F80826C,
    RECV2   = 0x1F808270,
    RECV3   = 0x1F808274,
    ISTAT   = 0x1F808280,
};

u32 ctrl;

u32 read(u32 addr) {
    switch (addr) {
        default:
            std::printf("[SIO2      ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write(u32 addr, u32 data) {
    switch (addr) {
        case SIO2Reg::CTRL:
            std::printf("[SIO2      ] 32-bit write @ CTRL = 0x%08X\n", data);

            ctrl = data;

            if ((ctrl & 0xC) == 0xC) {
                std::printf("[SIO2      ] SIO2 reset\n");

                /* TODO: reset FIFOS */

                dmac::setDRQ(Channel::SIO2IN, true);
                dmac::setDRQ(Channel::SIO2OUT, false);

                ctrl &= ~0xC;
            }

            if (data & 1) {
                std::printf("[SIO2      ] Unhandled command chain\n");

                exit(0);
            }

            break;
        default:
            std::printf("[SIO2      ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

}
