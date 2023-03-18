/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "sio2.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <queue>

#include "../dmac/dmac.hpp"
#include "../../intc.hpp"

namespace ps2::iop::sio2 {

using Channel = dmac::Channel;
using IOPInterrupt = intc::IOPInterrupt;

/* --- SIF constants --- */

constexpr int FIFO_SIZE = 256;

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

enum DevStatus {
    NotConnected = 0x1D100,
};

u32 recv1;

u32 ctrl;

std::queue<u32> send3;
std::queue<u8>  in, out;

/* Executes an SIO2 command chain */
void doCmdChain() {
    std::printf("[SIO2      ] New command chain\n");

    assert(send3.size());

    while (send3.size()) {
        const auto data = send3.front();

        send3.pop();

        const auto port = data & 3;

        const auto len = (data >> 18) & 0x3F;

        std::printf("[SIO2      ] New command; port = %u, length = %u\n", port, len);

        /* Discard items in input FIFO, send reply bytes */
        for (u32 i = 0; i < len; i++) {
            in.pop();
            out.push(0);
        }
    }

    while (!in.empty()) { in.pop(); out.push(0); }

    dmac::setDRQ(Channel::SIO2OUT, true);

    recv1 = DevStatus::NotConnected;

    intc::sendInterruptIOP(IOPInterrupt::SIO2);
}

u32 read(u32 addr) {
    switch (addr) {
        case SIO2Reg::CTRL:
            std::printf("[SIO2      ] 32-bit read @ CTRL\n");
            return ctrl;
        case SIO2Reg::RECV1:
            std::printf("[SIO2      ] 32-bit read @ RECV1\n");
            return recv1;
        case SIO2Reg::RECV2:
            std::printf("[SIO2      ] 32-bit read @ RECV2\n");
            return 0xF; // Always 0xF?
        case SIO2Reg::RECV3:
            std::printf("[SIO2      ] 32-bit read @ RECV3\n");
            return 0; // Maybe?
        case SIO2Reg::ISTAT:
            std::printf("[SIO2      ] 32-bit read @ ISTAT\n");
            return 0; // Should be okay
        default:
            std::printf("[SIO2      ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

/* Reads data from FIFO_OUT */
u8 readFIFO() {
    assert(out.size() > 0);

    std::printf("[SIO2      ] Read @ FIFO_OUT\n");

    const auto data = out.front();

    out.pop();

    return data;
}

/* Reads data from FIFO_OUT via DMA */
u32 readDMAC() {
    assert(out.size() > 3);

    std::printf("[SIO2      ] Read @ FIFO_OUT\n");

    u32 data = out.front(); out.pop();

    data |= out.front() <<  8; out.pop();
    data |= out.front() << 16; out.pop();
    data |= out.front() << 24; out.pop();

    return data;
}

void write(u32 addr, u32 data) {
    if ((addr >= SIO2Reg::SEND3) && (addr < (SIO2Reg::SEND3 + 0x40))) {
        std::printf("[SIO2      ] 32-bit write @ SEND3 = 0x%08X\n", data);

        if (data) {
            send3.push(data);
        }

        return;
    } else if ((addr >= SIO2Reg::SEND1) && (addr < (SIO2Reg::SEND1 + 0x20))) {
        if (addr & 4) {
            std::printf("[SIO2      ] 32-bit write @ SEND2 = 0x%08X\n", data);
        } else {
            std::printf("[SIO2      ] 32-bit write @ SEND1 = 0x%08X\n", data);
        }

        return;
    }

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
                doCmdChain();

                ctrl &= ~1;
            }

            break;
        case SIO2Reg::ISTAT:
            std::printf("[SIO2      ] 32-bit write @ ISTAT = 0x%08X\n", data);
            break;
        default:
            std::printf("[SIO2      ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

/* Writes data to FIFOIN */
void writeFIFO(u8 data) {
    assert(in.size() < FIFO_SIZE);

    std::printf("[SIO2      ] Write @ FIFO_IN = 0x%02X\n", data);

    in.push(data);
}

/* Writes data to FIFOIN via DMAC */
void writeDMAC(u32 data) {
    assert(in.size() <= (FIFO_SIZE - 4));

    std::printf("[SIO2      ] Write @ FIFO_IN[%lu] = 0x%08X\n", in.size(), data);

    in.push(data);
    in.push(data >>  8);
    in.push(data >> 16);
    in.push(data >> 24);
}

}
