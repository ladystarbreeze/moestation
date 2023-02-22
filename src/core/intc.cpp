/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "intc.hpp"

#include <cassert>
#include <cstdio>

/* --- INTC registers --- */

u16 intcMASK = 0; // EE interrupt mask

namespace ps2::intc {

u16 readMask() {
    return intcMASK;
}

}
