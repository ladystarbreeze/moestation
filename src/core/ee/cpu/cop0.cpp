/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "cop0.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::ee::cpu::cop0 {

/* --- COP0 register definitions --- */

enum class COP0Reg {
    Index    = 0x00,
    Random   = 0x01,
    EntryLo0 = 0x02,
    EntryLo1 = 0x03,
    Context  = 0x04,
    PageMask = 0x05,
    Wired    = 0x06,
    BadVAddr = 0x08,
    Count    = 0x09,
    EntryHi  = 0x0A,
    Compare  = 0x0B,
    Status   = 0x0C,
    Cause    = 0x0D,
    EPC      = 0x0E,
    PRId     = 0x0F,
    Config   = 0x10,
    BadPAddr = 0x17,
    Debug    = 0x18,
    Perf     = 0x19,
    TagLo    = 0x1C,
    TagHi    = 0x1D,
    ErrorEPC = 0x1E,
};

/* --- COP0 registers --- */

struct Status {
    bool ie;       // Interrupt Enable
    bool exl, erl; // EXception/ERror Level
    u8   ksu;      // Kernel/Supervisor/User
    bool bem;      // Bus Error Mask
    u8   im;       // Interrupt Mask
    bool eie;      // Enable IE bit
    bool edi;      // EI/DI Instruction enable
    bool ch;       // Cache Hit
    bool bev;      // Boot Exception Vectors
    bool dev;      // Debug Exception Vectors
    u8   cu;       // Coprocessor Usable
};

Status status;

u32 count, compare;

void init() {
    status.erl = true;
    status.bev = true;

    count = compare = 0;
}

/* Returns a COP0 register (32-bit) */
u32 get32(u32 idx) {
    assert(idx < 32);

    u32 data;

    switch (idx) {
        case static_cast<u32>(COP0Reg::Count): data = count; break;
        case static_cast<u32>(COP0Reg::PRId ): data = (0x2E << 8) | 0x10; break; // Implementation number 0x2E, major version 1, minor version 0
        default:
            std::printf("[COP0:EE   ] Unhandled register read @ %u\n", idx);

            exit(0);
    }

    return data;
}

/* Sets a COP0 register (32-bit) */
void set32(u32 idx, u32 data) {
    assert(idx < 32);

    switch (idx) {
        case static_cast<u32>(COP0Reg::Index   ): break;
        case static_cast<u32>(COP0Reg::EntryLo0): break;
        case static_cast<u32>(COP0Reg::EntryLo1): break;
        case static_cast<u32>(COP0Reg::PageMask): break;
        case static_cast<u32>(COP0Reg::Wired   ): break;
        case static_cast<u32>(COP0Reg::Count   ): count = data; break;
        case static_cast<u32>(COP0Reg::EntryHi ): break;
        case static_cast<u32>(COP0Reg::Compare ): 
            compare = data;

            /* TODO: clear COMPARE interrupt! */
            break;
        case static_cast<u32>(COP0Reg::Status):
            status.ie  = data & (1 << 0);
            status.exl = data & (1 << 1);
            status.erl = data & (1 << 2);
            status.ksu = (data >>  3) & 3;
            status.im  = (data >> 10) & 3;
            status.bem = data & (1 << 12);
            status.im |= (data >> 13) & 4;
            status.eie = data & (1 << 16);
            status.edi = data & (1 << 17);
            status.ch  = data & (1 << 18);
            status.bev = data & (1 << 22);
            status.dev = data & (1 << 23);
            status.cu  = (data >> 28) & 0xF;
            break;
        case static_cast<u32>(COP0Reg::Config): break;
        default:
            std::printf("[COP0:EE   ] Unhandled register write @ %u = 0x%08X\n", idx, data);

            exit(0);
    }
}

/* Increments Count, checks for COMPARE interrupts */
void incrementCount(i64 c) {
    count += c;

    /* TODO: COMPARE interrupts */
}

}
