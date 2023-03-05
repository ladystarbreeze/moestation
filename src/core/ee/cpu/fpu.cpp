/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "fpu.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::ee::cpu::fpu {

/* --- FPU constants --- */

constexpr auto doDisasm = true;

/* --- FPU instructions --- */

enum FPUOpcode {
    ADDA = 0x18,
    MADD = 0x1C,
};

/* --- FPU registers --- */

f32 fprs[32];
f32 acc;

/// Get Fd field
u32 getFd(u32 instr) {
    return (instr >> 6) & 0x1F;
}

/// Get Fs field
u32 getFs(u32 instr) {
    return (instr >> 11) & 0x1F;
}

/// Get Ft field
u32 getFt(u32 instr) {
    return (instr >> 16) & 0x1F;
}

void setAcc(f32 data) {
    std::printf("[FPU       ] ACC = %f\n", data);

    acc = data;
}

/* ADD Accumulator */
void iADDA(u32 instr) {
    const auto fs = getFs(instr);
    const auto ft = getFt(instr);

    if (doDisasm) {
        std::printf("[FPU       ] ADDA $%u, $%u\n", fs, ft);
    }

    setAcc(get(fs) + get(ft));
}

/* Multiply-ADD */
void iMADD(u32 instr) {
    const auto fd = getFd(instr);
    const auto fs = getFs(instr);
    const auto ft = getFt(instr);

    if (doDisasm) {
        std::printf("[FPU       ] MADD $%u, $%u, $%u\n", fd, fs, ft);
    }

    set(fd, get(fs) * get(ft) + acc);
}

f32 get(u32 idx) {
    return fprs[idx];
}

u32 getControl(u32 idx) {
    switch (idx) {
        case 31:
            std::printf("[FPU       ] Control read @ FCR31\n");
            return 0;
        default:
            std::printf("[FPU       ] Unhandled control read @ %u\n", idx);

            exit(0);
    }
}

void set(u32 idx, f32 data) {
    std::printf("[FPU       ] %u = %f\n", idx, data);

    fprs[idx] = data;
}

void setControl(u32 idx, u32 data) {
    switch (idx) {
        case 31:
            std::printf("[FPU       ] Control write @ FCR31 = 0x%08X\n", data);
            break;
        default:
            std::printf("[FPU       ] Unhandled control write @ %u = 0x%08X\n", idx, data);

            exit(0);
    }
}

void executeSingle(u32 instr) {
    const auto opcode = instr & 0x3F;

    switch (opcode) {
        case FPUOpcode::ADDA: iADDA(instr); break;
        case FPUOpcode::MADD: iMADD(instr); break;
        default:
            std::printf("[FPU       ] Unhandled Single instruction 0x%02X (0x%08X)\n", opcode, instr);

            exit(0);
    }
}

}
