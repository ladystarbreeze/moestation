/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../common/types.hpp"

namespace ps2::intc {

/* EE interrupt sources */
enum class Interrupt {
    GS,
    SBUS,
    VBLANKStart, VBLANKEnd,
    VIF0, VIF1,
    VU0, VU1,
    IPU,
    Timer0, Timer1, Timer2, Timer3, /* EE timer interrupts */
    SFIFO,
    VU0Watchdog,
};

/* IOP interrupt sources */
enum class IOPInterrupt {
    VBLANKStart,
    GPU,
    CDVD,
    DMA,
    Timer0, Timer1, Timer2, /* IOP timer interrupts */
    SIO0, SIO1, /* Serial I/O interrupts */
    SPU2,
    PIO,
    VBLANKEnd,
    DVD,
    PCMCIA,
    Timer3, Timer4, Timer5, /* IOP timer interrupts */
    SIO2,
    HTR0, HTR1, HTR2, HTR3,
    USB,
    EXTR,
    FWRE, FDMA, /* FireWire interrupts */
};

u16 readMask();
u16 readStat();

u32 readMaskIOP();
u32 readStatIOP();
u32 readCtrlIOP();

void writeMask(u16 data);
void writeStat(u16 data);

void writeMaskIOP(u32 data);
void writeStatIOP(u32 data);
void writeCtrlIOP(u32 data);

void sendInterrupt(Interrupt i);
void sendInterruptIOP(IOPInterrupt i);

}
