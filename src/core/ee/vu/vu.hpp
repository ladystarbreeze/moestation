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
    u32 getVF(u32 idx, int e);
    f32 getVF_F32(u32 idx, int e);
    u16 getVI(u32 idx);

    f32 getQ();

    void writeData32(u32 addr, u32 data);

    void setControl(u32 idx, u32 data); // VU0 only
    void setVF(u32 idx, int e, u32 data);
    void setVF(u32 idx, int e, f32 data);
    void setVI(u32 idx, u16 data);

    void setQ(f32 data);
    
    int vuID;

private:
    VectorUnit *otherVU;

    u32 vf[33][4]; // Floating-point registers (+ accumulator)
    u16 vi[16];    // Integer registers

    f32 q;
};

}
