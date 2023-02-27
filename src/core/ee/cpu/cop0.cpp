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

struct Cause {
    u8   excode; // Exception code
    u8   ip;     // Interrupt pending
    u8   ercode; // Error code
    u8   ce;     // Coprocessor error
    bool bd2;    // Branch delay (level 2)
    bool bd;     // Branch delay
};

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

Cause cause;
Status status;

u32 epc, errorEPC;

u32 count, compare;

void init() {
    status.erl = true;
    status.bev = true;

    count = compare = 0;
}

/* Increments Count, checks for COMPARE interrupts */
void incrementCount(i64 c) {
    count += c;

    /* TODO: COMPARE interrupts */
}

/* Returns a COP0 register (32-bit) */
u32 get32(u32 idx) {
    assert(idx < 32);

    u32 data;

    switch (idx) {
        case static_cast<u32>(COP0Reg::BadVAddr): return 0;
        case static_cast<u32>(COP0Reg::Count   ): return count;
        case static_cast<u32>(COP0Reg::Status  ):
            data  = status.ie;
            data |= status.exl << 1;
            data |= status.erl << 2;
            data |= status.ksu << 3;
            data |= (status.im & 3) << 10;
            data |= status.bem << 12;
            data |= (status.im & 4) << 13;
            data |= status.eie << 16;
            data |= status.edi << 17;
            data |= status.ch  << 18;
            data |= status.bev << 22;
            data |= status.dev << 23;
            data |= status.cu  << 28;
            break;
        case static_cast<u32>(COP0Reg::Cause):
            data  = cause.excode << 2;
            data |= (cause.ip & 3) << 10;
            data |= (cause.ip & 4) << 13;
            data |= cause.ercode << 16;
            data |= cause.ce  << 28;
            data |= cause.bd2 << 30;
            data |= cause.bd  << 31;
            break;
        case static_cast<u32>(COP0Reg::EPC  ): return epc;
        case static_cast<u32>(COP0Reg::PRId ): return (0x2E << 8) | 0x10; // Implementation number 0x2E, major version 1, minor version 0
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
        case static_cast<u32>(COP0Reg::EPC   ):
            epc = data;
            break;
        default:
            std::printf("[COP0:EE   ] Unhandled register write @ %u = 0x%08X\n", idx, data);

            exit(0);
    }
}

/* Returns true if BEV is set */
bool isBEV() {
    return status.bev;
}

/* Returns true if EDI is set */
bool isEDI() {
    return status.edi;
}

/* Returns true if ERL is set */
bool isERL() {
    return status.erl;
}

/* Returns true if EXL is set */
bool isEXL() {
    return status.exl;
}

/* Sets BD */
void setBD(bool bd) {
    cause.bd = bd;
}

/* Sets EIE */
void setEIE(bool eie) {
    status.eie = eie;
}

/* Sets ERL */
void setERL(bool erl) {
    status.erl = erl;
}

/* Sets EXL */
void setEXL(bool exl) {
    status.exl = exl;
}

/* Returns EPC */
u32 getEPC() {
    return epc;
}

/* Returns ErrorEPC */
u32 getErrorEPC() {
    return errorEPC;
}

/* Sets EPC */
void setEPC(u32 pc) {
    epc = pc;
}

}
