/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "intc.hpp"

#include <cassert>
#include <cstdio>

#include "ee/cpu/cop0.hpp"
#include "iop/cop0.hpp"

namespace ps2::intc {

/* EE interrupt sources */
const char *intNames[] = {
    "GS",
    "SBUS",
    "VBLANK Start", "VBLANK End",
    "VIF0", "VIF1",
    "VU0", "VU1",
    "IPU",
    "Timer 0", "Timer 1", "Timer 2", "Timer 3", /* EE timer interrupts */
    "SFIFO",
    "VU0 Watchdog",
};

/* IOP interrupt sources */
const char *iopIntNames[] = {
    "VBLANK Start",
    "GPU",
    "CDVD",
    "DMA",
    "Timer 0", "Timer 1", "Timer 2", /* IOP timer interrupts */
    "SIO0", "SIO1", /* Serial I/O interrupts */
    "SPU2",
    "PIO",
    "VBLANK End",
    "DVD",
    "PCMCIA",
    "Timer 3", "Timer 4", "Timer 5", /* IOP timer interrupts */
    "SIO2",
    "HTR0", "HTR1", "HTR2", "HTR3",
    "USB",
    "EXTR",
    "FireWire", "FDMA", /* FireWire interrupts */
};

/* --- INTC registers --- */

/* EE interrupt registers */
u16 intcMASK = 0, intcSTAT = 0;

/* IOP interrupt registers */
u32 iMASK = 0, iSTAT = 0;
bool iCTRL = false;

void checkInterrupt();
void checkInterruptIOP();

/* Returns INTC_MASK */
u16 readMask() {
    return intcMASK;
}

/* Returns INTC_STAT */
u16 readStat() {
    return intcSTAT;
}

/* Returns I_MASK */
u32 readMaskIOP() {
    return iMASK;
}

/* Returns I_STAT */
u32 readStatIOP() {
    return iSTAT;
}

/* Returns I_CTRL */
u32 readCtrlIOP() {
    const auto oldCTRL = iCTRL;

    /* Reading I_CTRL turns off interrupts */
    iCTRL = false;

    checkInterruptIOP();

    return oldCTRL;
}

/* Writes INTC_MASK */
void writeMask(u16 data) {
    intcMASK ^= (data & 0x7FFF);

    checkInterrupt();
}

/* Writes INTC_STAT */
void writeStat(u16 data) {
    intcSTAT &= (~data & 0x7FFF);

    checkInterrupt();
}

/* Writes I_MASK */
void writeMaskIOP(u32 data) {
    iMASK = data & 0x3FFFFFF;

    checkInterruptIOP();
}

/* Writes I_STAT */
void writeStatIOP(u32 data) {
    iSTAT &= data;

    checkInterruptIOP();
}

/* Writes I_CTRL */
void writeCtrlIOP(u32 data) {
    iCTRL = data & 1;

    checkInterruptIOP();
}

void sendInterrupt(Interrupt i) {
    std::printf("[INTC:EE   ] %s interrupt request\n", intNames[static_cast<int>(i)]);

    intcSTAT |= 1 << static_cast<int>(i);

    checkInterrupt();
}

void sendInterruptIOP(IOPInterrupt i) {
    std::printf("[INTC:IOP  ] %s interrupt request\n", iopIntNames[static_cast<int>(i)]);

    iSTAT |= 1 << static_cast<int>(i);

    checkInterruptIOP();
}

void checkInterrupt() {
    //std::printf("[INTC:EE   ] INTC_STAT = 0x%04X, INTC_MASK = 0x%04X\n", intcSTAT, intcMASK);

    ee::cpu::cop0::setInterruptPending(intcSTAT & intcMASK);
}

void checkInterruptIOP() {
    //std::printf("[INTC:IOP  ] I_CTRL = %d, I_STAT = 0x%07X, I_MASK = 0x%07X\n", iCTRL, iSTAT, iMASK);

    iop::cop0::setInterruptPending(iCTRL && (iSTAT & iMASK));
}

}
