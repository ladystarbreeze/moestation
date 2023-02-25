/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "intc.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::intc {

/* --- INTC registers --- */

/* EE interrupt registers */
u16 intcMASK = 0, intcSTAT = 0;

/* IOP interrupt registers */
u32 iMASK = 0, iSTAT = 0;
bool iCTRL = false;

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

    return oldCTRL;
}

/* Writes INTC_MASK */
void writeMask(u16 data) {
    intcMASK = (intcMASK ^ data) & 0x7FFF;
}

/* Writes INTC_STAT */
void writeStat(u16 data) {
    intcSTAT = (intcSTAT & ~data) & 0x7FFF;
}

/* Writes I_MASK */
void writeMaskIOP(u32 data) {
    iMASK = data & 0x3FFFFFF;
}

/* Writes I_STAT */
void writeStatIOP(u32 data) {
    iSTAT = (iSTAT & ~data) & 0x3FFFFFF;
}

/* Writes I_CTRL */
void writeCtrlIOP(u32 data) {
    iCTRL = data & 1;
}

}
