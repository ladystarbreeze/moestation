/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "gif.hpp"

#include <cassert>
#include <cstdio>

namespace ps2::gif {

const char *fmtNames[4] = { "PACKED", "REGLIST", "IMAGE", "IMAGE" };

/* GIFtag formats */
enum Format {
    PACKED,
    REGLIST,
    IMAGE,
};

/* --- GIF registers --- */

enum GIFReg {
    CTRL = 0x10003000,
    STAT = 0x10003020,
};

/* GIFtag */
struct GIFtag {
    u128 tag;

    /* GIFtag fields */

    u16  nloop; // Number of loop iterations
    bool eop;   // End of Packet
    bool prim;  // PRIM write
    u16  pdata; // PRIM data
    u8   nregs; // Number of registers
    u64  regs;  // Register list

    Format fmt;

    bool hasTag;
};

GIFtag gifTag;

u16 nloop = 0, nregs = 0;

/* Decodes GIFtags */
void decodeTag(const u128 &data) {
    std::printf("[GIF       ] New GIFtag = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);

    gifTag.tag = data;

    gifTag.nloop = data._u16[0] & 0x7FFF;
    gifTag.eop   = data._u16[0] & (1 << 15);
    gifTag.prim  = data._u64[0] & (1ull << 46);
    gifTag.pdata = (data._u64[0] >> 47) & 0x7FF;
    gifTag.nregs = (data._u64[0] >> 60);
    gifTag.regs  = data._u64[1];

    assert(gifTag.nloop);

    /* NREGS = 0 means 16 */
    if (!gifTag.nregs) gifTag.nregs = 16;

    switch ((data._u64[0] >> 58) & 3) {
        case 0: gifTag.fmt = Format::PACKED;  break;
        case 1: gifTag.fmt = Format::REGLIST; break;
        default:
            gifTag.fmt = Format::IMAGE;
    }

    gifTag.hasTag = true;

    /* TODO: initialize GS Q register */
}

/* Handles IMAGE transfers */
void doIMAGE(const u128 &data) {
    if (nloop == gifTag.nloop) std::printf("[GIF       ] IMAGE transfer; NLOOP = %u\n", gifTag.nloop);

    /* TODO: write data to HWREG */
    std::printf("[GIF       ] IMAGE write = 0x%016llX\n[GIF       ] IMAGE write = 0x%016llX\n", data._u64[0], data._u64[1]);

    nloop--;

    if (!nloop) {
        std::printf("[GIF       ] IMAGE transfer end\n");

        gifTag.hasTag = false;
    }
}

/* Handles PACKED transfers */
void doPACKED(const u128 &data) {
    if (!nregs && (nloop == gifTag.nloop)) std::printf("[GIF       ] PACKED transfer; NREGS = %u, NLOOP = %u\n", gifTag.nregs, gifTag.nloop);

    const auto reg = (gifTag.regs >> (4 * nregs)) & 0xF;

    /* TODO: write data to GS */
    std::printf("[GIF       ] PACKED write @ 0x%02llX = 0x%016llX%016llX\n", reg, data._u64[1], data._u64[0]);

    nregs++;

    if (nregs == gifTag.nregs) {
        nloop--;

        if (!nloop) {
            std::printf("[GIF       ] PACKED transfer end\n");

            gifTag.hasTag = false;
        }

        nregs = 0;
    }
}

/* Handles GIF packets */
void doCmd(const u128 &data) {
    if (!gifTag.hasTag) {
        /* Set up GIFtag */

        decodeTag(data);

        assert(gifTag.nloop);
        assert(!gifTag.prim);

        nloop = gifTag.nloop;
        nregs = 0;

        return;
    }

    switch (gifTag.fmt) {
        case Format::PACKED: doPACKED(data); break;
        case Format::IMAGE : doIMAGE(data); break;
        default:
            std::printf("[GIF       ] Unhandled %s format\n", fmtNames[gifTag.fmt]);

            exit(0);
    }
}

/* Returns a GIF register */
u32 read(u32 addr) {
    u32 data;

    switch (addr) {
        case GIFReg::STAT:
            std::printf("[GIF       ] Read @ GIF_STAT\n");
            return 0;
        default:
            std::printf("[GIF       ] Unhandled read @ 0x%08X\n", addr);

            exit(0);
    }

    return data;
}

/* Writes a GIF register */
void write(u32 addr, u32 data) {
    switch (addr) {
        case GIFReg::CTRL:
            std::printf("[GIF       ] Write @ GIF_CTRL = 0x%08X\n", data);

            if (data & 1) std::printf("[GIF       ] GIF reset\n");
            break;
        default:
            std::printf("[GIF       ] Unhandled write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

void writePATH3(const u128 &data) {
    /* TODO: PATH arbitration? */

    //std::printf("[GIF:PATH3 ] Write = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);

    doCmd(data);
}

}
