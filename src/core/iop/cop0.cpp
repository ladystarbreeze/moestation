/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "cop0.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::iop::cop0 {

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
    Debug    = 0x18,
    TagLo    = 0x1C,
    TagHi    = 0x1D,
    ErrorEPC = 0x1E,
};

void init() {
    /* TODO: set BEV */
}

/* Returns a COP0 register */
u32 get(u32 idx) {
    assert(idx < 32);

    u32 data;

    switch (idx) {
        case static_cast<u32>(COP0Reg::PRId): data = 0x1F; break; // Probably not correct, but good enough for the BIOS
        default:
            std::printf("[COP0:IOP  ] Unhandled register read @ %u\n", idx);

            exit(0);
    }

    return data;
}

}
