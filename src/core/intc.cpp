/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "intc.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::intc {

/* --- INTC registers --- */

u16 intcMASK = 0, intcSTAT = 0; // EE interrupt registers

/* Returns INTC_MASK */
u16 readMask() {
    return intcMASK;
}

/* Returns INTC_STAT */
u16 readStat() {
    return intcSTAT;
}

/* Writes INTC_MASK */
void writeMask(u16 data) {
    intcMASK = (intcMASK ^ data) & 0x7FFF;
}

/* Writes INTC_STAT */
void writeStat(u16 data) {
    intcSTAT = (intcSTAT & ~data) & 0x7FFF;
}

}
