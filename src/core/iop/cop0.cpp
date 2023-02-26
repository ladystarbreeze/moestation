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
    BPC      = 0x03,
    BDA      = 0x05,
    JumpDest = 0x06,
    DCIC     = 0x07,
    BadVAddr = 0x08,
    BDAM     = 0x09,
    BPCM     = 0x0B,
    Status   = 0x0C,
    Cause    = 0x0D,
    EPC      = 0x0E,
    PRId     = 0x0F,
};

/* COP0 Cause register */
struct Cause {
    u8   excode; // EXception CODE
    u8   ip;     // Interrupt Pending
    u8   ce;     // Coprocessor Error
    bool bd;     // Branch Delay
};

/* COP0 Status register */
struct Status {
    bool cie; // Current Interrupt Enable
    bool cku; // Current Kernel/User mode
    bool pie; // Previous Interrupt Enable
    bool pku; // Previous Kernel/User mode
    bool oie; // Old Interrupt Enable
    bool oku; // Old Kernel/User mode
    u8   im;  // Interrupt Mask
    bool isc; // ISolate Cache
    bool swc; // SWap Caches
    bool pz;  // cache Parity Zero
    bool ch;  // Cache Hit
    bool pe;  // cache Parity Error
    bool ts;  // TLB Shutdown
    bool bev; // Boot Exception Vectors
    bool re;  // Reverse Endianness
    u8   cu;  // Coprocessor Usable
};

Cause cause;
Status status;

u32 epc; // Exception program counter

void init() {
    status.bev = true;
}

/* Returns a COP0 register */
u32 get(u32 idx) {
    assert(idx < 32);

    u32 data;

    switch (idx) {
        case static_cast<u32>(COP0Reg::Status):
            data  = status.cie;
            data |= status.cku <<  1;
            data |= status.pie <<  2;
            data |= status.pku <<  3;
            data |= status.oie <<  4;
            data |= status.oku <<  5;
            data |= status.im  <<  8;
            data |= status.isc << 16;
            data |= status.swc << 17;
            data |= status.pz  << 18;
            data |= status.ch  << 19;
            data |= status.pe  << 20;
            data |= status.ts  << 21;
            data |= status.bev << 22;
            data |= status.re  << 25;
            data |= status.cu  << 28;
            break;
        case static_cast<u32>(COP0Reg::Cause):
            data  = cause.excode << 2;
            data |= cause.ip << 8;
            data |= cause.ce << 28;
            data |= cause.bd << 31;
            break;
        case static_cast<u32>(COP0Reg::EPC ): data = epc; break;
        case static_cast<u32>(COP0Reg::PRId): data = 0x1F; break; // Probably not correct, but good enough for the BIOS
        default:
            std::printf("[COP0:IOP  ] Unhandled register read @ %u\n", idx);

            exit(0);
    }

    return data;
}

/* Sets a COP0 register */
void set(u32 idx, u32 data) {
    switch (idx) {
        case static_cast<u32>(COP0Reg::BPC     ): break;
        case static_cast<u32>(COP0Reg::BDA     ): break;
        case static_cast<u32>(COP0Reg::JumpDest): break;
        case static_cast<u32>(COP0Reg::DCIC    ): break;
        case static_cast<u32>(COP0Reg::BDAM    ): break;
        case static_cast<u32>(COP0Reg::BPCM    ): break;
        case static_cast<u32>(COP0Reg::Status  ):
            status.cie = data & (1 << 0);
            status.cku = data & (1 << 1);
            status.pie = data & (1 << 2);
            status.pku = data & (1 << 3);
            status.oie = data & (1 << 4);
            status.oku = data & (1 << 5);
            status.im  = (data >> 8) & 0xFF;
            status.isc = data & (1 << 16);
            status.swc = data & (1 << 17);
            status.pz  = data & (1 << 18);
            status.ch  = data & (1 << 19);
            status.pe  = data & (1 << 20);
            status.ts  = data & (1 << 21);
            status.bev = data & (1 << 22);
            status.re  = data & (1 << 25);
            status.cu  = (data >> 28) & 0xF;
            break;
        case static_cast<u32>(COP0Reg::Cause):
            cause.ip = (data >> 8) & 0xF;
            break;
        default:
            std::printf("[COP0:IOP  ] Unhandled register write @ %u = 0x%08X\n", idx, data);

            exit(0);
    }
}

/* Sets exception code, saves privilege level and interrupt enable bit */
void enterException(Exception e) {
    cause.excode = e;

    /* Push interrupt enable */
    status.oie = status.pie;
    status.pie = status.cie;
    status.cie = false;

    /* Push privilege level */
    status.oku = status.pku;
    status.pku = status.cku;
    status.cku = true;
}

/* Restores privilege level and interrupt enable bit */
void leaveException() {
    /* Pop interrupt enable */
    status.cie = status.pie;
    status.pie = status.oie;
    status.oie = false;

    /* Pop privilege level */
    status.cku = status.pku;
    status.pku = status.oku;
    status.oku = false;
}

/* Returns true if BEV is set */
bool isBEV() {
    return status.bev;
}

/* Returns true if IsC bit is set */
bool isCacheIsolated() {
    return status.isc;
}

/* Sets the BD bit in Cause */
void setBD(bool bd) {
    cause.bd = bd;
}

/* Sets the exception program counter */
void setEPC(u32 pc) {
    epc = pc;
}

}
