/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include "../vu/vu.hpp"
#include "../../../common/types.hpp"

using VectorUnit = ps2::ee::vu::VectorUnit;

namespace ps2::ee::vif {

struct VectorInterface {
    VectorInterface(int vifID, VectorUnit *vu);

    void write(u32 addr, u32 data);

private:
    int vifID;

    VectorUnit *vu;
};

}
