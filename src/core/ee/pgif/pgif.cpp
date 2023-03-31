/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "pgif.hpp"

#include <cassert>
#include <cstdio>
#include <queue>

namespace ps2::ee::pgif {

/* --- PGIF registers --- */

enum class PGIFReg {
    PGPUSTAT = 0x1000F300,
    IMME2    = 0x1000F310,
    IMME3    = 0x1000F320,
    IMME4    = 0x1000F330,
    IMME5    = 0x1000F340,
    PGIFCTRL = 0x1000F380,
    PGPUCMD  = 0x1000F3C0,
    PGPUDATA = 0x1000F3E0,
};

u32 pgpustat;
u32 pgifctrl;

u32 imm[4];

std::queue<u32> pgpucmd;
std::queue<u32> pgpudata;

u32 read(u32 addr) {
    u32 data;

    switch (addr) {
        case static_cast<u32>(PGIFReg::PGPUSTAT):
            std::printf("[PGIF      ] 32-bit read @ PGPU_STAT\n");
            return pgpustat;
        case static_cast<u32>(PGIFReg::PGIFCTRL):
            std::printf("[PGIF      ] 32-bit read @ PGIF_CTRL\n");

            data  = pgifctrl;
            data |= (pgpudata.size() & 0x1F) << 8;
            data |= (pgpucmd.size()  & 0x07) << 16;
            data |= pgpudata.empty() << 20;
            break;
        case static_cast<u32>(PGIFReg::PGPUDATA):
            std::printf("[PGIF      ] 32-bit read @ PGPU_DATA\n");
            
            data = pgpudata.front(); pgpudata.pop();
            break;
        default:
            std::printf("[PGIF      ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }

    return data;
}

u32 readGPUSTAT() {
    std::printf("[PGPU      ] 32-bit read @ GPUSTAT\n");

    return pgpustat;
}

void write(u32 addr, u32 data) {
    switch (addr) {
        case static_cast<u32>(PGIFReg::PGPUSTAT):
            std::printf("[PGIF      ] 32-bit write @ PGPU_STAT = 0x%08X\n", data);

            pgpustat = data;
            break;
        case static_cast<u32>(PGIFReg::IMME2):
            std::printf("[PGIF      ] 32-bit write @ IMM_E2 = 0x%08X\n", data);

            imm[0] = data;
            break;
        case static_cast<u32>(PGIFReg::IMME3):
            std::printf("[PGIF      ] 32-bit write @ IMM_E3 = 0x%08X\n", data);

            imm[1] = data;
            break;
        case static_cast<u32>(PGIFReg::IMME4):
            std::printf("[PGIF      ] 32-bit write @ IMM_E4 = 0x%08X\n", data);

            imm[2] = data;
            break;
        case static_cast<u32>(PGIFReg::IMME5):
            std::printf("[PGIF      ] 32-bit write @ IMM_E5 = 0x%08X\n", data);

            imm[3] = data;
            break;
        case static_cast<u32>(PGIFReg::PGIFCTRL):
            std::printf("[PGIF      ] 32-bit write @ PGIF_CTRL = 0x%08X\n", data);

            pgifctrl = data;
            break;
        default:
            std::printf("[PGIF      ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);
            
            exit(0);
    }
}

void writeGP0(u32 data) {
    std::printf("[PGPU      ] 32-bit write @ GP0 = 0x%08X\n", data);

    pgpudata.push(data);
}

void writeGP1(u32 data) {
    std::printf("[PGPU      ] 32-bit write @ GP0 = 0x%08X\n", data);

    if ((data >> 4) == 1) {
        /* GP0(0x10...0x1F) need to respond immediately, don't push to FIFO */
    } else {
        pgpucmd.push(data);
    }
}

}
