/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../../../common/types.hpp"

static const char *elementStr[4] = {"X", "Y", "Z", "W"};

namespace ps2::ee::vu {

struct VectorUnit {
    VectorUnit(int vuID, VectorUnit *otherVU);

    void reset();
    void forceBreak();

    u32 getControl(u32 idx); // VU0 only
    f32 getVF(u32 idx, int e);
    u16 getVI(u32 idx);

    void writeData32(u32 addr, u32 data);

    void setControl(u32 idx, u32 data); // VU0 only
    void setVF(u32 idx, int e, f32 data);
    void setVI(u32 idx, u16 data);
    
    int vuID;

private:
    VectorUnit *otherVU;

    f32 vf[32][4]; // Floating-point registers
    u16 vi[16];    // Integer registers
};

}
