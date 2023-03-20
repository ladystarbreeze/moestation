/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "gs.hpp"

#include <algorithm>
#include <cassert>
#include <cstdio>
#include <queue>
#include <vector>

#include "../intc.hpp"
#include "../scheduler.hpp"
#include "../ee/timer/timer.hpp"
#include "../iop/timer/timer.hpp"

namespace ps2::gs {

using Interrupt = intc::Interrupt;
using IOPInterrupt = intc::IOPInterrupt;

/* --- GS constants --- */

constexpr i64 CYCLES_PER_SCANLINE = 2 * 9370; // NTSC, converted to EE clock
constexpr i64 SCANLINES_PER_VDRAW = 240;
constexpr i64 SCANLINES_PER_FRAME = 262;

static const i32 primVertexCount[8] = { 1, 2, 2, 3, 3, 3, 2, 1 };

/* GS primitives */
enum Primitive {
    Point, Line, LineStrip, Triangle, TriangleStrip, TriangleFan, Sprite, Prohibited,
};

/* Pixel storage mode */
enum PSM {
    PSMCT32  = 0x00,
    PSMCT24  = 0x01,
    PSMCT16  = 0x02,
    PSMCT16S = 0x0A,
    PSMCT8   = 0x13,
    PSMCT4   = 0x14,
    PSMCT4HL = 0x24,
    PSMCT4HH = 0x2C,
    PSMZ32   = 0x30,
    PSMZ24   = 0x32,
    PSMZ16   = 0x32,
    PSMZ16S  = 0x3A,
};

/* Transmission direction */
enum TRXDIR {
    HostToLocal,
    LocalToHost,
    LocalToLocal,
    Deactivated,
};

/* Z test method */
enum class ZTest {
    Never, Always, GEqual, Greater,
};

struct Vertex {
    /* Coordinates */

    i64 x, y, z;

    /* Colors */

    i64 r, g, b, a, f;

    /* Texel coordinates */

    i64 u, v;

    /* Texture coordinates */

    f32 s, t, q;
};

/* --- GS registers --- */

/* GS internal registers */
enum class GSReg {
    PRIM       = 0x00,
    RGBAQ      = 0x01,
    ST         = 0x02,
    UV         = 0x03,
    XYZF2      = 0x04,
    XYZ2       = 0x05,
    TEX0_1     = 0x06,
    TEX0_2     = 0x07,
    CLAMP_1    = 0x08,
    CLAMP_2    = 0x09,
    FOG        = 0x0A,
    XYZF3      = 0x0C,
    XYZ3       = 0x0D,
    ADDRDATA   = 0x0E,
    NOP        = 0x0F,
    TEX1_1     = 0x14,
    TEX1_2     = 0x15,
    TEX2_1     = 0x16,
    TEX2_2     = 0x17,
    XYOFFSET_1 = 0x18,
    XYOFFSET_2 = 0x19,
    PRMODECONT = 0x1A,
    PRMODE     = 0x1B,
    TEXCLUT    = 0x1C,
    SCANMSK    = 0x22,
    MIPTBP1_1  = 0x34,
    MIPTBP1_2  = 0x35,
    MIPTBP2_1  = 0x36,
    MIPTBP2_2  = 0x37,
    TEXA       = 0x3B,
    FOGCOL     = 0x3D,
    TEXFLUSH   = 0x3F,
    SCISSOR_1  = 0x40,
    SCISSOR_2  = 0x41,
    ALPHA_1    = 0x42,
    ALPHA_2    = 0x43,
    DIMX       = 0x44,
    DTHE       = 0x45,
    COLCLAMP   = 0x46,
    TEST_1     = 0x47,
    TEST_2     = 0x48,
    PABE       = 0x49,
    FBA_1      = 0x4A,
    FBA_2      = 0x4B,
    FRAME_1    = 0x4C,
    FRAME_2    = 0x4D,
    ZBUF_1     = 0x4E,
    ZBUF_2     = 0x4F,
    BITBLTBUF  = 0x50,
    TRXPOS     = 0x51,
    TRXREG     = 0x52,
    TRXDIR     = 0x53,
    HWREG      = 0x54,
    SIGNAL     = 0x60,
    FINISH     = 0x61,
    LABEL      = 0x62,
};

/* GS privileged registers */
enum PrivReg {
    PMODE    = 0x12000000,
    SMODE1   = 0x12000010,
    SMODE2   = 0x12000020,
    SRFSH    = 0x12000030,
    SYNCH1   = 0x12000040,
    SYNCH2   = 0x12000050,
    SYNCV    = 0x12000060,
    DISPFB2  = 0x12000090,
    DISPLAY2 = 0x120000A0,
    BGCOLOR  = 0x120000E0,
    CSR      = 0x12001000,
    IMR      = 0x12001010,
};

/* Bit blit buffers */
struct BITBLTBUF {
    u32 sbp;  // Source buffer pointer
    u32 sbw;  // Source buffer width
    u8  spsm; // Source pixel storage mode
    u32 dbp;  // Destination buffer pointer
    u32 dbw;  // Destination buffer width
    u8  dpsm; // Destination pixel storage mode
};

/* Frame buffer control */
struct FRAME {
    u32 fbp;   // Frame buffer pointer
    u32 fbw;   // Frame buffer width
    u8  psm;   // Pixel storage mode
    u32 fbmsk; // Frame buffer mask
};

/* Primitive control */
struct PRIM {
    u8   prim; // Primitive (not in PRMODE)
    bool iip;  // Gouraud shading
    bool tme;  // Texture mapping
    bool fge;  // Fogging
    bool abe;  // Alpha blending
    bool aa1;  // 1-pass antialiasing
    bool fst;  // UV tex coords
    bool ctxt; // Current context
    bool fix;  // Fixed fragment value
};

/* Vertex color setting */
struct RGBAQ {
    u8  r, g, b, a;
    f32 q;
};

/* Scissor test setting */
struct SCISSOR {
    i64 scax0;
    i64 scax1;
    i64 scay0;
    i64 scay1;
};

/* Pixel test setting */
struct TEST {
    bool ate;   // Alpha test enable
    u8   atst;  // Alpha test method
    u8   aref;  // Reference alpha
    u8   afail; // Fail processing method
    bool date;  // Destination alpha test enable
    bool datm;  // Destination alpha test mode
    bool zte;   // Z test enable
    u8   ztst;  // Z test method
};

/* Transmission area position */
struct TRXPOS {
    u32 ssax;
    u32 ssay;
    u32 dsax;
    u32 dsay;
    u8  dir;
};

/* Transmission area register */
struct TRXREG {
    u32 rrw;
    u32 rrh;
};

/* XY offset */
struct XYOFFSET {
    i64 ofx;
    i64 ofy;
};

/* Depth buffer control */
struct ZBUF {
    u32  zbp;  // Z buffer pointer
    u8   psm;  // Pixel storage mode
    bool zmsk; // Z buffer mask
};

/* GS context */
struct Context {
    FRAME    frame;
    SCISSOR  scissor;
    TEST     test;
    XYOFFSET xyoffset;
    ZBUF     zbuf;
};

/* Transmission info */
struct TRXInfo {
    u32 x, y;
};

Context ctx[2]; // The GS has two drawing environment contexts
Context *cctx;  // Current context

TRXInfo srcTrx, dstTrx;

PRIM prim, prmode;
PRIM *cmode; // Current primitive mode

RGBAQ rgbaq;

BITBLTBUF bitbltbuf;
TRXPOS    trxpos;
TRXREG    trxreg;
u8        trxdir;

bool colclamp;

u64 csr;

std::vector<u32> vram;

Vertex vtxQueue[3];
i32 vtxCount;

i64 lineCounter = 0;

/* GS scheduler event IDs */
u64 idHBLANK;

void doTransmission();
void drawSprite();

/* Handles HBLANK events */
void hblankEvent(i64 c) {
    ee::timer::stepHBLANK();
    iop::timer::stepHBLANK();

    csr |= 1 << 2; // HBLANK

    ++lineCounter;

    if (lineCounter == SCANLINES_PER_VDRAW) {
        intc::sendInterrupt(Interrupt::VBLANKStart);
        intc::sendInterruptIOP(IOPInterrupt::VBLANKStart);

        csr |= 1 << 3;  // VBLANK
        csr ^= 1 << 13; // FIELD
    } else if (lineCounter == SCANLINES_PER_FRAME) {
        intc::sendInterrupt(Interrupt::VBLANKEnd);
        intc::sendInterruptIOP(IOPInterrupt::VBLANKEnd);

        lineCounter = 0;
    }
    
    scheduler::addEvent(idHBLANK, 0, CYCLES_PER_SCANLINE + c, false);
}

/* Registers GS events */
void init() {
    vram.resize(2048 * 2048 / 4); // 4 MB

    idHBLANK = scheduler::registerEvent([](int, i64 c) { hblankEvent(c); });

    scheduler::addEvent(idHBLANK, 0, CYCLES_PER_SCANLINE, true);
}

void initQ() {
    rgbaq.q = 1.0;
}

u64 readPriv(u32 addr) {
    switch (addr) {
        case PrivReg::CSR:
            //std::printf("[GS        ] Unhandled 64-bit read @ CSR\n");
            return csr | 2;
        default:
            std::printf("[GS        ] Unhandled 64-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

/* Writes a GS privileged register */
void writePriv(u32 addr, u64 data) {
    switch (addr) {
        case PrivReg::PMODE:
            std::printf("[GS        ] 64-bit write @ PMODE = 0x%016llX\n", data);
            break;
        case PrivReg::SMODE1:
            std::printf("[GS        ] 64-bit write @ SMODE1 = 0x%016llX\n", data);
            break;
        case PrivReg::SMODE2:
            std::printf("[GS        ] 64-bit write @ SMODE2 = 0x%016llX\n", data);
            break;
        case PrivReg::SRFSH:
            std::printf("[GS        ] 64-bit write @ SRFSH = 0x%016llX\n", data);
            break;
        case PrivReg::SYNCH1:
            std::printf("[GS        ] 64-bit write @ SYNCH1 = 0x%016llX\n", data);
            break;
        case PrivReg::SYNCH2:
            std::printf("[GS        ] 64-bit write @ SYNCH2 = 0x%016llX\n", data);
            break;
        case PrivReg::SYNCV:
            std::printf("[GS        ] 64-bit write @ SYNCV = 0x%016llX\n", data);
            break;
        case PrivReg::DISPFB2:
            std::printf("[GS        ] 64-bit write @ DISPFB2 = 0x%016llX\n", data);
            break;
        case PrivReg::DISPLAY2:
            std::printf("[GS        ] 64-bit write @ DISPLAY2 = 0x%016llX\n", data);
            break;
        case PrivReg::BGCOLOR:
            std::printf("[GS        ] 64-bit write @ BGCOLOR = 0x%016llX\n", data);
            break;
        case PrivReg::CSR:
            std::printf("[GS        ] 64-bit write @ CSR = 0x%016llX\n", data);

            csr = data;
            break;
        case PrivReg::IMR:
            std::printf("[GS        ] 64-bit write @ IMR = 0x%016llX\n", data);
            break;
        default:
            std::printf("[GS        ] Unhandled 64-bit write @ 0x%08X = 0x%016llX\n", addr, data);

            exit(0);
    }
}

/* Writes data to an internal GS register */
void write(u8 addr, u64 data) {
    switch (addr) {
        case static_cast<u8>(GSReg::PRIM):
            std::printf("[GS        ] Write @ PRIM = 0x%016llX\n", data);

            prim.prim = data & 7;
            prim.iip  = data & (1 << 3);
            prim.tme  = data & (1 << 4);
            prim.fge  = data & (1 << 5);
            prim.abe  = data & (1 << 6);
            prim.aa1  = data & (1 << 7);
            prim.fst  = data & (1 << 8);
            prim.ctxt = data & (1 << 9);
            prim.fix  = data & (1 << 10);

            cctx = &ctx[cmode->ctxt]; // Set active context
            break;
        case static_cast<u8>(GSReg::RGBAQ):
            {
            std::printf("[GS        ] Write @ RGBAQ = 0x%016llX\n", data);

            rgbaq.r = (data >>  0);
            rgbaq.g = (data >>  8);
            rgbaq.b = (data >> 16);
            rgbaq.a = (data >> 24);

            const auto q = (u32)(data >> 32) & ~0xFF; // Clear low 8 bits of mantissa

            rgbaq.q = *(f32 *)&q;
            }
            break;
        case static_cast<u8>(GSReg::XYZ2):
            {
                std::printf("[GS        ] Write @ XYZ2 = 0x%016llX\n", data);

                assert(vtxCount < 4);

                Vertex vtx;

                vtx.x = (i64)((data >>  0) & 0xFFFF);
                vtx.y = (i64)((data >> 16) & 0xFFFF);

                vtx.z = (i64)(data >> 32);

                vtx.r = rgbaq.r;
                vtx.g = rgbaq.g;
                vtx.b = rgbaq.b;
                vtx.a = rgbaq.a;

                //vtx.u = uv.u;
                //vtx.v = uv.v;

                //vtx.s = st.s;
                //vtx.t = st.t;
                vtx.q = rgbaq.q;

                vtxQueue[vtxCount++] = vtx;

                if (vtxCount == primVertexCount[prim.prim]) {
                    switch (prim.prim) {
                        case Primitive::Sprite: drawSprite(); break;
                        default:
                            std::printf("[GS        ] Unhandled primitive %u\n", prim.prim);

                            exit(0);
                    }

                    vtxCount = 0;
                }
            }
            break;
        case static_cast<u8>(GSReg::XYOFFSET_1):
            {
                std::printf("[GS        ] Write @ XYOFFSET1 = 0x%016llX\n", data);

                auto &xyoffset = ctx[0].xyoffset;

                xyoffset.ofx = (i64)((data >>  0) & 0xFFFF);
                xyoffset.ofy = (i64)((data >> 32) & 0xFFFF);
            }
            break;
        case static_cast<u8>(GSReg::XYOFFSET_2):
            {
                std::printf("[GS        ] Write @ XYOFFSET2 = 0x%016llX\n", data);

                auto &xyoffset = ctx[1].xyoffset;

                xyoffset.ofx = (i64)((data >>  0) & 0xFFFF);
                xyoffset.ofy = (i64)((data >> 32) & 0xFFFF);
            }
            break;
        case static_cast<u8>(GSReg::PRMODECONT):
            std::printf("[GS        ] Write @ PRMODECONT = 0x%016llX\n", data);

            cmode = (data & 1) ? &prim : &prmode;

            cctx = &ctx[cmode->ctxt]; // Set active context
            break;
        case static_cast<u8>(GSReg::TEXFLUSH):
            std::printf("[GS        ] Write @ TEXFLUSH = 0x%016llX\n", data);
            break;
        case static_cast<u8>(GSReg::SCISSOR_1):
            {
                std::printf("[GS        ] Write @ SCISSOR1 = 0x%016llX\n", data);

                auto &scissor = ctx[0].scissor;

                scissor.scax0 = (i64)((data >>  0) & 0x7FF);
                scissor.scax1 = (i64)((data >> 16) & 0x7FF);
                scissor.scay0 = (i64)((data >> 32) & 0x7FF);
                scissor.scay1 = (i64)((data >> 48) & 0x7FF);
            }
            break;
        case static_cast<u8>(GSReg::SCISSOR_2):
            {
                std::printf("[GS        ] Write @ SCISSOR2 = 0x%016llX\n", data);

                auto &scissor = ctx[1].scissor;

                /* Multiply by 16 so we don't have to do this later */

                scissor.scax0 = (i64)((data >>  0) & 0x7FF) << 4;
                scissor.scax1 = (i64)((data >> 16) & 0x7FF) << 4;
                scissor.scay0 = (i64)((data >> 32) & 0x7FF) << 4;
                scissor.scay1 = (i64)((data >> 48) & 0x7FF) << 4;
            }
            break;
        case static_cast<u8>(GSReg::DTHE):
            std::printf("[GS        ] Write @ DTHE = 0x%016llX\n", data);
            break;
        case static_cast<u8>(GSReg::COLCLAMP):
            std::printf("[GS        ] Write @ COLCLAMP = 0x%016llX\n", data);

            colclamp = data & 1;
            break;
        case static_cast<u8>(GSReg::TEST_1):
            {
                std::printf("[GS        ] Write @ TEST1 = 0x%016llX\n", data);

                auto &test = ctx[0].test;

                test.ate   = data & 1;
                test.atst  = (data >> 1) & 7;
                test.aref  = (data >> 4);
                test.afail = (data >> 12) & 3;
                test.date  = data & (1 << 14);
                test.datm  = data & (1 << 15);
                test.zte   = data & (1 << 16);
                test.ztst  = (data >> 17) & 3;
            }
            break;
        case static_cast<u8>(GSReg::TEST_2):
            {
                std::printf("[GS        ] Write @ TEST2 = 0x%016llX\n", data);

                auto &test = ctx[1].test;

                test.ate   = data & 1;
                test.atst  = (data >> 1) & 7;
                test.aref  = (data >> 4);
                test.afail = (data >> 12) & 3;
                test.date  = data & (1 << 14);
                test.datm  = data & (1 << 15);
                test.zte   = data & (1 << 16);
                test.ztst  = (data >> 17) & 3;
            }
            break;
        case static_cast<u8>(GSReg::FRAME_1):
            {
                std::printf("[GS        ] Write @ FRAME1 = 0x%016llX\n", data);

                auto &frame = ctx[0].frame;

                frame.fbp   = 2048 * (data & 0x1FF);      // Multiply by 2048 now so we don't have to do this every time we read/write VRAM
                frame.fbw   = 64 * ((data >> 16) & 0x3F); // Same as above
                frame.psm   = (data >> 24) & 0x3F;
                frame.fbmsk = data >> 32;
            }
            break;
        case static_cast<u8>(GSReg::FRAME_2):
            {
                std::printf("[GS        ] Write @ FRAME2 = 0x%016llX\n", data);
                
                auto &frame = ctx[1].frame;

                frame.fbp   = 2048 * (data & 0x1FF);      // Multiply by 2048 now so we don't have to do this every time we read/write VRAM
                frame.fbw   = 64 * ((data >> 16) & 0x3F); // Same as above
                frame.psm   = (data >> 24) & 0x3F;
                frame.fbmsk = data >> 32;
            }
            break;
        case static_cast<u8>(GSReg::ZBUF_1):
            {
                std::printf("[GS        ] Write @ ZBUF1 = 0x%016llX\n", data);

                auto &zbuf = ctx[0].zbuf;

                zbuf.zbp  = 2048 * (data & 0x1FF);      // Multiply by 2048 now so we don't have to do this every time we read/write VRAM
                zbuf.psm  = 0x30 | ((data >> 24) & 0xF);
                zbuf.zmsk = data & (1ull << 32);
            }
            break;
        case static_cast<u8>(GSReg::ZBUF_2):
            {
                std::printf("[GS        ] Write @ ZBUF2 = 0x%016llX\n", data);

                auto &zbuf = ctx[1].zbuf;

                zbuf.zbp  = 2048 * (data & 0x1FF);      // Multiply by 2048 now so we don't have to do this every time we read/write VRAM
                zbuf.psm  = 0x30 | ((data >> 24) & 0xF);
                zbuf.zmsk = data & (1ull << 32);
            }
            break;
        case static_cast<u8>(GSReg::BITBLTBUF):
            std::printf("[GS        ] Write @ BITBLTBUF = 0x%016llX\n", data);

            bitbltbuf.sbp   = 64 * (data & 0x1FFF);       // Multiply by 2048 now so we don't have to do this every time we read/write VRAM
            bitbltbuf.sbw   = 64 * ((data >> 16) & 0x3F); // Same as above
            bitbltbuf.spsm  = (data >> 24) & 0x3F;
            bitbltbuf.dbp   = 64 * ((data >> 32) & 0x1FFF);
            bitbltbuf.dbw   = 64 * ((data >> 48) & 0x3F);
            bitbltbuf.dpsm  = (data >> 56) & 0x3F;
            break;
        case static_cast<u8>(GSReg::TRXPOS):
            std::printf("[GS        ] Write @ TRXPOS = 0x%016llX\n", data);

            trxpos.ssax = (data >>  0) & 0x7FF;
            trxpos.ssay = (data >> 16) & 0x7FF;
            trxpos.dsax = (data >> 32) & 0x7FF;
            trxpos.dsay = (data >> 48) & 0x7FF;
            trxpos.dir  = (data >> 59) & 3;
            break;
        case static_cast<u8>(GSReg::TRXREG):
            std::printf("[GS        ] Write @ TRXREG = 0x%016llX\n", data);

            trxreg.rrw = (data >>  0) & 0xFFF;
            trxreg.rrh = (data >> 32) & 0xFFF;
            break;
        case static_cast<u8>(GSReg::TRXDIR):
            {
                std::printf("[GS        ] Write @ TRXDIR = 0x%016llX\n", data);

                trxdir = data & 3;

                doTransmission();
            }
            break;
        case static_cast<u8>(GSReg::FINISH):
            std::printf("[GS        ] Write @ FINISH = 0x%016llX\n", data);
            break;
        default:
            std::printf("[GS        ] Unhandled write @ 0x%02X = 0x%016llX\n", addr, data);

            exit(0);
    }
}

/* Unpacks data to an internal GS register */
void writePACKED(u8 addr, const u128 &data) {
    switch (addr) {
        case static_cast<u8>(GSReg::ADDRDATA):
            write(data._u8[8], data._u64[0]);
            break;
        default:
            std::printf("[GS        ] Unhandled PACKED write @ 0x%02X = 0x%016llX%016llX\n", addr, data._u64[1], data._u64[0]);

            exit(0);
    }
}

/* --- VRAM accessors --- */

template <PSM psm>
u32 readVRAM(u32 base, u32 width, u32 x, u32 y) {
    u32 addr = base;
    switch (psm) {
        case PSM::PSMCT32 :
        case PSM::PSMCT24 :
        case PSM::PSMCT4HL:
        case PSM::PSMCT4HH:
        case PSM::PSMZ24  :
            addr += x + width * y;
            break;
        case PSM::PSMCT16 :
        case PSM::PSMCT16S:
        case PSM::PSMZ16S :
            addr += (x >> 1) + ((width * y) >> 1);
            break;
        default:
            std::printf("[GS        ] Unhandled pixel storage mode 0x%02X\n", psm);

            exit(0);
    }

    addr &= 0xFFFFFF;

    switch (psm) {
        case PSM::PSMCT32:
            return vram[addr];
        case PSM::PSMCT24:
        case PSM::PSMZ24 :
            return vram[addr] & 0xFFFFFF;
        case PSM::PSMCT16 :
        case PSM::PSMCT16S:
        case PSM::PSMZ16S :
            return (vram[addr] >> (16 * (x & 1))) & 0xFFFF;
        case PSM::PSMCT4HL:
            return (vram[addr] >> 24) & 0xF;
            break;
        case PSM::PSMCT4HH:
            return vram[addr] >> 28;
            break;
        default:
            std::printf("[GS        ] Unhandled pixel storage mode 0x%02X\n", psm);

            exit(0);
    }
}

template <PSM psm>
void writeVRAM(u32 base, u32 width, u32 x, u32 y, u32 data) {
    u32 addr = base;
    switch (psm) {
        case PSM::PSMCT32 :
        case PSM::PSMCT24 :
        case PSM::PSMCT4HL:
        case PSM::PSMCT4HH:
        case PSM::PSMZ24  :
            addr += x + width * y;
            break;
        case PSM::PSMCT16 :
        case PSM::PSMCT16S:
        case PSM::PSMZ16S :
            addr += (x >> 1) + ((width * y) >> 1);
            break;
        default:
            std::printf("[GS        ] Unhandled pixel storage mode 0x%02X\n", psm);

            exit(0);
    }

    addr &= 0xFFFFFF;

    switch (psm) {
        case PSM::PSMCT32:
            vram[addr] = data;
            break;
        case PSM::PSMCT24:
        case PSM::PSMZ24 :
            vram[addr] = (vram[addr] & ~0xFF) | (data & 0xFFFFFF);
            break;
        case PSM::PSMCT16 :
        case PSM::PSMCT16S:
        case PSM::PSMZ16S :
            if (x & 1) {
                vram[addr] &= 0xFFFF;
                vram[addr] |= data << 16;
            } else {
                vram[addr] &= ~0xFFFF;
                vram[addr] |= data & 0xFFFF;
            }
            break;
        case PSM::PSMCT4HL:
            vram[addr] = (vram[addr] & ~(0xF << 24)) | (data << 24);
            break;
        case PSM::PSMCT4HH:
            vram[addr] = (vram[addr] & ~(0xF << 28)) | (data << 28);
            break;
        default:
            std::printf("[GS        ] Unhandled pixel storage mode 0x%02X\n", psm);

            exit(0);
    }
}

/* Writes data to HWREG */
void writeHWREG(u64 data) {
    std::printf("[GS        ] Write @ HWREG = 0x%016llX\n", data);

    if (trxdir != TRXDIR::HostToLocal) return;

    const auto x = trxpos.dsax + dstTrx.x;
    const auto y = trxpos.dsay + dstTrx.y;

    /* Unpack data according to PSM */

    switch (bitbltbuf.dpsm) {
        case PSM::PSMCT32:
            writeVRAM<PSM::PSMCT32>(bitbltbuf.dbp, bitbltbuf.dbw, x + 0, y, data);
            writeVRAM<PSM::PSMCT32>(bitbltbuf.dbp, bitbltbuf.dbw, x + 1, y, data);

            dstTrx.x += 2;
            break;
        case PSM::PSMCT16:
            for (int i = 0; i < 4; i++) {
                writeVRAM<PSM::PSMCT16>(bitbltbuf.dbp, bitbltbuf.dbw, x + i, y, (data >> (16 * i)) & 0xFFFF);
            }

            dstTrx.x += 4;
            break;
        case PSM::PSMCT4HL:
            for (int i = 0; i < 16; i++) {
                writeVRAM<PSM::PSMCT4HL>(bitbltbuf.dbp, bitbltbuf.dbw, x + i, y, (data >> (4 * i)) & 0xF);
            }

            dstTrx.x += 16;
            break;
        case PSM::PSMCT4HH:
            for (int i = 0; i < 16; i++) {
                writeVRAM<PSM::PSMCT4HH>(bitbltbuf.dbp, bitbltbuf.dbw, x + i, y, (data >> (4 * i)) & 0xF);
            }

            dstTrx.x += 16;
            break;
        default:
            std::printf("[GS        ] Unhandled pixel storage mode 0x%02X\n", bitbltbuf.dpsm);

            exit(0);
    }

    if (dstTrx.x >= trxreg.rrw) {
        dstTrx.y++;

        if (dstTrx.y >= trxreg.rrh) {
            std::printf("[GS        ] Host->Local transmission end\n");

            trxdir = TRXDIR::Deactivated;

            return;
        }

        dstTrx.x = 0;
    }
}

/* Performs a depth test */
bool depthTest(i64 x, i64 y, i64 z) {
    if (!cctx->test.zte) return true; // Shouldn't happen

    u32 oldZ;
    switch (cctx->zbuf.psm) {
        //case PSM::PSMZ24 : oldZ = readVRAM<PSM::PSMZ24 >(cctx->zbuf.zbp, cctx->frame.fbw, x, y); break;
        case PSM::PSMZ16S: oldZ = readVRAM<PSM::PSMZ16S>(cctx->zbuf.zbp, cctx->frame.fbw, x, y); break;
        default:
            std::printf("[GS        ] Unhandled depth storage mode 0x%02X\n", cctx->zbuf.psm);

            exit(0);
    }

    switch (cctx->test.ztst) {
        case static_cast<u8>(ZTest::Never) : return false;
        case static_cast<u8>(ZTest::Always): break;
        case static_cast<u8>(ZTest::GEqual):
            switch (cctx->zbuf.psm) {
                //case PSM::PSMZ24 : z &= 0xFFFFFF; break;
                case PSM::PSMZ16S: z &= 0xFFFF; break;
                default:
                    std::printf("[GS        ] Unhandled depth storage mode 0x%02X\n", cctx->zbuf.psm);

                    exit(0);
            }

            if ((u32)z < oldZ) return false;
            break;
        case static_cast<u8>(ZTest::Greater):
            switch (cctx->zbuf.psm) {
                //case PSM::PSMZ24 : z &= 0xFFFFFF; break;
                case PSM::PSMZ16S: z &= 0xFFFF; break;
                default:
                    std::printf("[GS        ] Unhandled depth storage mode 0x%02X\n", cctx->zbuf.psm);

                    exit(0);
            }

            if ((u32)z <= oldZ) return false;
            break;
    }

    if (!cctx->zbuf.zmsk) { // TODO: check alpha test result
        switch (cctx->zbuf.psm) {
            //case PSM::PSMZ24 : writeVRAM<PSM::PSMZ24 >(cctx->zbuf.zbp, cctx->frame.fbw, x, y, z); break;
            case PSM::PSMZ16S: writeVRAM<PSM::PSMZ16S>(cctx->zbuf.zbp, cctx->frame.fbw, x, y, z); break;
            default:
                std::printf("[GS        ] Unhandled depth storage mode 0x%02X\n", cctx->zbuf.psm);

                exit(0);
        }
    }

    return true;
}

void drawSprite() {
    std::printf("Drawing sprite...\n");

    assert(!cmode->iip);
    assert(!cmode->tme); // TODO: add texture mapping
    assert(!cmode->fge); // TODO: add fog
    assert(!cmode->abe); // TODO: add alpha blending
    assert(!cmode->fst);

    /* Get two vertices */

    Vertex v0 = vtxQueue[0];
    Vertex v1 = vtxQueue[1];

    /* Offset coordinates */

    v0.x -= cctx->xyoffset.ofx;
    v0.y -= cctx->xyoffset.ofy;
    v1.x -= cctx->xyoffset.ofx;
    v1.y -= cctx->xyoffset.ofy;

    /* Calculate "bounding box" */

    const auto xMin = (std::max(std::min(v0.x, v1.x), cctx->scissor.scax0) >> 4) << 4;
    const auto xMax = (std::min(std::max(v0.x, v1.x), (cctx->scissor.scax1 + 0x10)) >> 4) << 4;
    const auto yMin = (std::max(std::min(v0.y, v1.y), cctx->scissor.scay0) >> 4) << 4;
    const auto yMax = (std::min(std::max(v0.y, v1.y), (cctx->scissor.scay1 + 0x10)) >> 4) << 4;

    std::printf("v0 = [%lld, %lld], v1 = [%lld, %lld]\n", v0.x >> 4, v0.y >> 4, v1.x >> 4, v1.y >> 4);

    /* Start drawing */

    for (auto y = yMin >> 4; y < (yMax >> 4); y++) {
        for (auto x = xMin >> 4; x < (xMax >> 4); x++) {
            u32 color = (v1.a << 24) | (v1.b << 16) | (v1.g << 8) | v1.r;

            /* Skip to next pixel if Z test fails */
            if (!depthTest(x, y, v1.z)) continue;

            /* Draw pixel */
            switch (cctx->frame.psm) {
            case PSM::PSMCT24: writeVRAM<PSM::PSMCT24>(cctx->zbuf.zbp, cctx->frame.fbw, x, y, color); break;
                default:
                    std::printf("[GS        ] Unhandled pixel storage mode 0x%02X\n", cctx->frame.psm);

                    exit(0);
            }
        }
    }
}

/* --- Transmission handlers --- */

void doTransmission() {
    switch (trxdir) {
        case TRXDIR::HostToLocal: // Handled via HWREG writes
            std::printf("[GS        ] Host->Local transmission\n");

            dstTrx.x = 0;
            dstTrx.y = 0;
            break;
        case TRXDIR::Deactivated:
            std::printf("[GS        ] Transmission deactivated\n");
            break;
        default:
            std::printf("[GS        ] Unhandled transmission direction %u\n", trxdir);
            exit(0);
    }
}

}
