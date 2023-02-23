/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

namespace ps2::ee::vu {

struct VectorUnit {
    VectorUnit(int vuID, VectorUnit *otherVU);

    void reset();
    void forceBreak();

    u32 getControl(u32 idx); // VU0 only

    void setControl(u32 idx, u32 data); // VU0 only
    
    int vuID;

private:
    VectorUnit *otherVU;

    u16 vi[16]; // Integer registers
};

}
