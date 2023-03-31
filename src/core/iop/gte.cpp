/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "gte.hpp"

#include <bit>
#include <cassert>
#include <cstdio>

namespace ps2::iop::gte {

typedef i16 Matrix[3][3];
typedef i16 Vec16[3];
typedef i32 Vec32[3];

/* --- GTE constants --- */

constexpr auto X = 0, Y = 1, Z = 2;
constexpr auto R = 0, G = 1, B = 2;

/* --- GTE instructions --- */

enum Opcode {
    RTPS  = 0x01,
    NCLIP = 0x06,
    MVMVA = 0x12,
    NCDS  = 0x13,
    SQR   = 0x28,
    AVSZ3 = 0x2D,
    AVSZ4 = 0x2E,
    RTPT  = 0x30,
    GPF   = 0x3D,
    GPL   = 0x3E,
    NCCT  = 0x3F,
};

/* --- GTE registers --- */

enum GTEReg {
    VXY0 = 0x00, VZ0  = 0x01,
    VXY1 = 0x02, VZ1  = 0x03,
    VXY2 = 0x04, VZ2  = 0x05,
    RGBC = 0x06,
    OTZ  = 0x07,
    IR0  = 0x08, IR1  = 0x09, IR2  = 0x0A, IR3  = 0x0B,
    SXY0 = 0x0C, SXY1 = 0x0D, SXY2 = 0x0E, SXYP = 0x0F,
    SZ0  = 0x10, SZ1  = 0x11, SZ2  = 0x12, SZ3  = 0x13,
    RGB0 = 0x14, RGB1 = 0x15, RGB2 = 0x16,
    MAC0 = 0x18, MAC1 = 0x19, MAC2 = 0x1A, MAC3 = 0x1B,
    LZCS = 0x1E, LZCR = 0x1F,
};

enum ControlReg {
    RT11RT12 = 0x00, RT13RT21 = 0x01, RT22RT23 = 0x02, RT31RT32 = 0x03, RT33 = 0x04,
    TRX      = 0x05, TRY      = 0x06, TRZ      = 0x07,
    L11L12   = 0x08, L13L21   = 0x09, L22L23   = 0x0A, L31L32   = 0x0B, L33  = 0x0C,
    RBK      = 0x0D, GBK      = 0x0E, BBK      = 0x0F,
    LR1LR2   = 0x10, LR3LG1   = 0x11, LG2LG3   = 0x12, LB1LB2   = 0x13, LB3  = 0x14,
    RFC      = 0x15, GFC      = 0x16, BFC      = 0x17,
    OFX      = 0x18, OFY      = 0x19,
    H        = 0x1A,
    DCA      = 0x1B, DCB      = 0x1C,
    ZSF3     = 0x1D, ZSF4     = 0x1E,
    FLAG     = 0x1F,
};

/* Light color matrix */
enum LCM {
    LR, LB, LG,
};

/* --- GTE registers --- */

Vec16 v[3];    // Vectors 0-2
u8    rgbc[4]; // Color/Code
u16   otz;
i16   ir[4];   // 16-bit Accumulators
i32   mac[4];  // Accumulators

u32 lzcs, lzcr; // Leading Zero Count Source/Result

/* --- GTE FIFOs --- */

u32 sxy[3]; // Screen X/Y (three entries)
u16 sz[4];  // Screen Z (four entries)
u32 rgb[3]; // Color/code FIFO

/* --- GTE control registers --- */

Matrix rt;            // Rotation matrix
Vec32  tr;            // Translation vector X/Y/Z
Matrix ls;            // Light source matrix
Vec32  bk;            // Background color R/G/B
Matrix lc;            // Light color matrix
Vec32  fc;            // Far color R/G/B
i32    ofx, ofy;      // Screen offset X/Y
u16    h;             // Projection plane distance
i16    dca;           // Depth cueing parameter A
i32    dcb;           // Depth cueing parameter B
i16    zsf3, zsf4;    // Z scale factors

int countLeadingBits(u32 a) {
    if (a & (1 << 31)) {
        return std::__countl_one(a);
    }

    return std::__countl_zero(a);
}

u32 get(u32 idx) {
    switch (idx) {
        case GTEReg::OTZ:
            //std::printf("[GTE       ] Read @ OTZ\n");
            return otz;
        case GTEReg::IR0:
            //std::printf("[GTE       ] Read @ IR0\n");
            return ir[0];
        case GTEReg::IR1:
            //std::printf("[GTE       ] Read @ IR1\n");
            return ir[1];
        case GTEReg::IR2:
            //std::printf("[GTE       ] Read @ IR2\n");
            return ir[2];
        case GTEReg::IR3:
            //std::printf("[GTE       ] Read @ IR3\n");
            return ir[3];
        case GTEReg::SXY0:
            //std::printf("[GTE       ] Read @ SXY0\n");
            return sxy[0];
        case GTEReg::SXY1:
            //std::printf("[GTE       ] Read @ SXY1\n");
            return sxy[1];
        case GTEReg::SXY2:
            //std::printf("[GTE       ] Read @ SXY2\n");
            return sxy[2];
        case GTEReg::SZ0:
            //std::printf("[GTE       ] Read @ SXY0\n");
            return sz[0];
        case GTEReg::SZ1:
            //std::printf("[GTE       ] Read @ SXY1\n");
            return sz[1];
        case GTEReg::SZ2:
            //std::printf("[GTE       ] Read @ SXY2\n");
            return sz[2];
        case GTEReg::SZ3:
            //std::printf("[GTE       ] Read @ SXY3\n");
            return sz[3];
        case GTEReg::RGB0:
            //std::printf("[GTE       ] Read @ RGB0\n");
            return rgb[0];
        case GTEReg::RGB1:
            //std::printf("[GTE       ] Read @ RGB1\n");
            return rgb[1];
        case GTEReg::RGB2:
            //std::printf("[GTE       ] Read @ RGB2\n");
            return rgb[2];
        case GTEReg::MAC0:
            //std::printf("[GTE       ] Read @ MAC0\n");
            return mac[0];
        case GTEReg::MAC1:
            //std::printf("[GTE       ] Read @ MAC1\n");
            return mac[1];
        case GTEReg::MAC2:
            //std::printf("[GTE       ] Read @ MAC2\n");
            return mac[2];
        case GTEReg::MAC3:
            //std::printf("[GTE       ] Read @ MAC3\n");
            return mac[3];
        case GTEReg::LZCS:
            //std::printf("[GTE       ] Read @ LZCS\n");
            return lzcs;
        case GTEReg::LZCR:
            //std::printf("[GTE       ] Read @ LZCR\n");
            return lzcr;
        default:
            std::printf("[GTE       ] Unhandled read @ %u\n", idx);

            exit(0);
    }
}

u32 getControl(u32 idx) {
    switch (idx) {
        case ControlReg::FLAG:
            //std::printf("[GTE       ] Control read @ FLAG\n");
            return 0;
        default:
            std::printf("[GTE       ] Unhandled control read @ %u\n", idx);

            exit(0);
    }
}

void set(u32 idx, u32 data) {
    switch (idx) {
        case GTEReg::VXY0:
            //std::printf("[GTE       ] Write @ VXY0 = 0x%08X\n", data);

            v[0][X] = data;
            v[0][Y] = data >> 16;
            break;
        case GTEReg::VZ0:
            //std::printf("[GTE       ] Write @ VZ0 = 0x%08X\n", data);

            v[0][Z] = data;
            break;
        case GTEReg::VXY1:
            //std::printf("[GTE       ] Write @ VXY1 = 0x%08X\n", data);

            v[1][X] = data;
            v[1][Y] = data >> 16;
            break;
        case GTEReg::VZ1:
            //std::printf("[GTE       ] Write @ VZ1 = 0x%08X\n", data);

            v[1][Z] = data;
            break;
        case GTEReg::VXY2:
            //std::printf("[GTE       ] Write @ VXY2 = 0x%08X\n", data);

            v[2][X] = data;
            v[2][Y] = data >> 16;
            break;
        case GTEReg::VZ2:
            //std::printf("[GTE       ] Write @ VZ2 = 0x%08X\n", data);

            v[2][Z] = data;
            break;
        case GTEReg::RGBC:
            //std::printf("[GTE       ] Write @ RGBC = 0x%08X\n", data);

            rgbc[0] = data;
            rgbc[1] = data >>  8;
            rgbc[2] = data >> 16;
            rgbc[3] = data >> 24;
            break;
        case GTEReg::IR0:
            //std::printf("[GTE       ] Write @ IR0 = 0x%08X\n", data);

            ir[0] = data;
            break;
        case GTEReg::IR1:
            //std::printf("[GTE       ] Write @ IR1 = 0x%08X\n", data);

            ir[1] = data;
            break;
        case GTEReg::IR2:
            //std::printf("[GTE       ] Write @ IR2 = 0x%08X\n", data);

            ir[2] = data;
            break;
        case GTEReg::IR3:
            //std::printf("[GTE       ] Write @ IR3 = 0x%08X\n", data);

            ir[3] = data;
            break;
        case GTEReg::RGB0:
            //std::printf("[GTE       ] Write @ RGB0 = 0x%08X\n", data);

            rgb[0] = data;
            break;
        case GTEReg::RGB1:
            //std::printf("[GTE       ] Write @ RGB1 = 0x%08X\n", data);

            rgb[1] = data;
            break;
        case GTEReg::RGB2:
            //std::printf("[GTE       ] Write @ RGB2 = 0x%08X\n", data);

            rgb[2] = data;
            break;
        case GTEReg::LZCS:
            //std::printf("[GTE       ] Write @ LZCS = 0x%08X\n", data);

            lzcs = data;
            lzcr = countLeadingBits(data);
            break;
        default:
            std::printf("[GTE       ] Unhandled write @ %u = 0x%08X\n", idx, data);

            exit(0);
    }
}

void setControl(u32 idx, u32 data) {
    switch (idx) {
        case ControlReg::RT11RT12:
            //std::printf("[GTE       ] Control write @ RT11RT12 = 0x%08X\n", data);

            rt[0][0] = data;
            rt[0][1] = data >> 16;
            break;
        case ControlReg::RT13RT21:
            //std::printf("[GTE       ] Control write @ RT13RT21 = 0x%08X\n", data);

            rt[0][2] = data;
            rt[1][0] = data >> 16;
            break;
        case ControlReg::RT22RT23:
            //std::printf("[GTE       ] Control write @ RT22RT23 = 0x%08X\n", data);

            rt[1][1] = data;
            rt[1][2] = data >> 16;
            break;
        case ControlReg::RT31RT32:
            //std::printf("[GTE       ] Control write @ RT31RT32 = 0x%08X\n", data);

            rt[2][0] = data;
            rt[2][1] = data >> 16;
            break;
        case ControlReg::RT33:
            //std::printf("[GTE       ] Control write @ RT33 = 0x%08X\n", data);

            rt[2][2] = data;
            break;
        case ControlReg::TRX:
            //std::printf("[GTE       ] Control write @ TRX = 0x%08X\n", data);

            tr[X] = data;
            break;
        case ControlReg::TRY:
            //std::printf("[GTE       ] Control write @ TRY = 0x%08X\n", data);

            tr[Y] = data;
            break;
        case ControlReg::TRZ:
            //std::printf("[GTE       ] Control write @ TRZ = 0x%08X\n", data);

            tr[Z] = data;
            break;
        case ControlReg::L11L12:
            //std::printf("[GTE       ] Control write @ L11L12 = 0x%08X\n", data);

            ls[0][0] = data;
            ls[0][1] = data >> 16;
            break;
        case ControlReg::L13L21:
            //std::printf("[GTE       ] Control write @ L13L21 = 0x%08X\n", data);

            ls[0][2] = data;
            ls[1][0] = data >> 16;
            break;
        case ControlReg::L22L23:
            //std::printf("[GTE       ] Control write @ L22L23 = 0x%08X\n", data);

            ls[1][1] = data;
            ls[1][2] = data >> 16;
            break;
        case ControlReg::L31L32:
            //std::printf("[GTE       ] Control write @ L31L32 = 0x%08X\n", data);

            ls[2][0] = data;
            ls[2][1] = data >> 16;
            break;
        case ControlReg::L33:
            //std::printf("[GTE       ] Control write @ L33 = 0x%08X\n", data);

            ls[2][2] = data;
            break;
        case ControlReg::RBK:
            //std::printf("[GTE       ] Control write @ RBK = 0x%08X\n", data);

            bk[R] = data;
            break;
        case ControlReg::GBK:
            //std::printf("[GTE       ] Control write @ GBK = 0x%08X\n", data);

            bk[G] = data;
            break;
        case ControlReg::BBK:
            //std::printf("[GTE       ] Control write @ BBK = 0x%08X\n", data);

            bk[B] = data;
            break;
        case ControlReg::LR1LR2:
            //std::printf("[GTE       ] Control write @ LR1LR2 = 0x%08X\n", data);

            lc[LCM::LR][0] = data;
            lc[LCM::LR][1] = data >> 16;
            break;
        case ControlReg::LR3LG1:
            //std::printf("[GTE       ] Control write @ LR3LG1 = 0x%08X\n", data);

            lc[LCM::LR][2] = data;
            lc[LCM::LG][0] = data >> 16;
            break;
        case ControlReg::LG2LG3:
            //std::printf("[GTE       ] Control write @ LG2LG3 = 0x%08X\n", data);

            lc[LCM::LG][1] = data;
            lc[LCM::LG][2] = data >> 16;
            break;
        case ControlReg::LB1LB2:
            //std::printf("[GTE       ] Control write @ LB1LB2 = 0x%08X\n", data);

            lc[LCM::LB][0] = data;
            lc[LCM::LB][1] = data >> 16;
            break;
        case ControlReg::LB3:
            //std::printf("[GTE       ] Control write @ LB3 = 0x%08X\n", data);

            lc[LCM::LB][2] = data;
            break;
        case ControlReg::RFC:
            //std::printf("[GTE       ] Control write @ RFC = 0x%08X\n", data);

            fc[R] = data;
            break;
        case ControlReg::GFC:
            //std::printf("[GTE       ] Control write @ GFC = 0x%08X\n", data);

            fc[G] = data;
            break;
        case ControlReg::BFC:
            //std::printf("[GTE       ] Control write @ BFC = 0x%08X\n", data);

            fc[B] = data;
            break;
        case ControlReg::OFX:
            //std::printf("[GTE       ] Control write @ OFX = 0x%08X\n", data);

            ofx = data;
            break;
        case ControlReg::OFY:
            //std::printf("[GTE       ] Control write @ OFY = 0x%08X\n", data);

            ofy = data;
            break;
        case ControlReg::H:
            //std::printf("[GTE       ] Control write @ H = 0x%08X\n", data);

            h = data;
            break;
        case ControlReg::DCA:
            //std::printf("[GTE       ] Control write @ DCA = 0x%08X\n", data);

            dca = data;
            break;
        case ControlReg::DCB:
            //std::printf("[GTE       ] Control write @ DCB = 0x%08X\n", data);

            dcb = data;
            break;
        case ControlReg::ZSF3:
            //std::printf("[GTE       ] Control write @ ZSF3 = 0x%08X\n", data);

            zsf3 = data;
            break;
        case ControlReg::ZSF4:
            //std::printf("[GTE       ] Control write @ ZSF4 = 0x%08X\n", data);

            zsf4 = data;
            break;
        default:
            std::printf("[GTE       ] Unhandled control write @ %u = 0x%08X\n", idx, data);

            exit(0);
    }
}

/* --- MAC/IR handlers --- */

/* Sets IR, performs clipping checks */
void setIR(u32 idx, i64 data, bool lm) {
    static const i64 IR_MIN[] = {      0, -0x8000, -0x8000, -0x8000 };
    static const i64 IR_MAX[] = { 0x1000,  0x7FFF,  0x7FFF,  0x7FFF };

    const auto irMin = (lm) ? 0 : IR_MIN[idx];

    /* Check for clipping */
    if (data > IR_MAX[idx]) {
        data = IR_MAX[idx];

        /* TODO: set IR overflow flags */
    } else if (data < irMin) {
        data = irMin;

        /* TODO: set IR overflow flags */
    }

    ir[idx] = data;
}

/* Sets MAC, performs overflow checks */
void setMAC(u32 idx, i64 data, int shift) {
    /* TODO: check for MAC overflow */

    /* Shift value, store low 32 bits of the result in MAC */
    mac[idx] = data >> shift;
}

/* Sets MAC and IR, performs overflow checks */
void setMACIR(u32 idx, i64 data, int shift, bool lm) {
    /* TODO: check for MAC overflow */

    /* Shift value, store low 32 bits of the result in MAC */
    mac[idx] = data >> shift;

    setIR(idx, mac[idx], lm);
}

/* Sign-extends MAC values */
i64 extsMAC(u32 idx, i64 data) {
    static const int MAC_WIDTH[] = { 31, 44, 44, 44 };

    /* TODO: check for MAC overflows */

    const int shift = 64 - MAC_WIDTH[idx];

    return (data << shift) >> shift;
}

/* GTE division (unsigned Newton-Raphson) */
u32 div(u32 a, u32 b) {
    static const u8 unrTable[] = {
		0xFF, 0xFD, 0xFB, 0xF9, 0xF7, 0xF5, 0xF3, 0xF1, 0xEF, 0xEE, 0xEC, 0xEA, 0xE8, 0xE6, 0xE4, 0xE3,
		0xE1, 0xDF, 0xDD, 0xDC, 0xDA, 0xD8, 0xD6, 0xD5, 0xD3, 0xD1, 0xD0, 0xCE, 0xCD, 0xCB, 0xC9, 0xC8,
		0xC6, 0xC5, 0xC3, 0xC1, 0xC0, 0xBE, 0xBD, 0xBB, 0xBA, 0xB8, 0xB7, 0xB5, 0xB4, 0xB2, 0xB1, 0xB0,
		0xAE, 0xAD, 0xAB, 0xAA, 0xA9, 0xA7, 0xA6, 0xA4, 0xA3, 0xA2, 0xA0, 0x9F, 0x9E, 0x9C, 0x9B, 0x9A,
		0x99, 0x97, 0x96, 0x95, 0x94, 0x92, 0x91, 0x90, 0x8F, 0x8D, 0x8C, 0x8B, 0x8A, 0x89, 0x87, 0x86,
		0x85, 0x84, 0x83, 0x82, 0x81, 0x7F, 0x7E, 0x7D, 0x7C, 0x7B, 0x7A, 0x79, 0x78, 0x77, 0x75, 0x74,
		0x73, 0x72, 0x71, 0x70, 0x6F, 0x6E, 0x6D, 0x6C, 0x6B, 0x6A, 0x69, 0x68, 0x67, 0x66, 0x65, 0x64,
		0x63, 0x62, 0x61, 0x60, 0x5F, 0x5E, 0x5D, 0x5D, 0x5C, 0x5B, 0x5A, 0x59, 0x58, 0x57, 0x56, 0x55,
		0x54, 0x53, 0x53, 0x52, 0x51, 0x50, 0x4F, 0x4E, 0x4D, 0x4D, 0x4C, 0x4B, 0x4A, 0x49, 0x48, 0x48,
		0x47, 0x46, 0x45, 0x44, 0x43, 0x43, 0x42, 0x41, 0x40, 0x3F, 0x3F, 0x3E, 0x3D, 0x3C, 0x3C, 0x3B,
		0x3A, 0x39, 0x39, 0x38, 0x37, 0x36, 0x36, 0x35, 0x34, 0x33, 0x33, 0x32, 0x31, 0x31, 0x30, 0x2F,
		0x2E, 0x2E, 0x2D, 0x2C, 0x2C, 0x2B, 0x2A, 0x2A, 0x29, 0x28, 0x28, 0x27, 0x26, 0x26, 0x25, 0x24,
		0x24, 0x23, 0x22, 0x22, 0x21, 0x20, 0x20, 0x1F, 0x1E, 0x1E, 0x1D, 0x1D, 0x1C, 0x1B, 0x1B, 0x1A,
		0x19, 0x19, 0x18, 0x18, 0x17, 0x16, 0x16, 0x15, 0x15, 0x14, 0x14, 0x13, 0x12, 0x12, 0x11, 0x11,
		0x10, 0x0F, 0x0F, 0x0E, 0x0E, 0x0D, 0x0D, 0x0C, 0x0C, 0x0B, 0x0A, 0x0A, 0x09, 0x09, 0x08, 0x08,
		0x07, 0x07, 0x06, 0x06, 0x05, 0x05, 0x04, 0x04, 0x03, 0x03, 0x02, 0x02, 0x01, 0x01, 0x00, 0x00,
		0x00,
	};

    if ((2 * b) <= a) {
        /* TODO: set overflow flags */

        return 0x1FFFF;
    }

    const auto shift = std::__countl_zero(b);

    a <<= shift;
    b <<= shift;

    const auto u = 0x101 + unrTable[(b + 0x40) >> 7];

    b |= 0x8000;

    auto d = ((b * -u) + 0x80) >> 8;

    d = ((u * (0x20000 + d)) + 0x80) >> 8;

    const auto n = (a * d + 0x8000) >> 16;

    if (n > 0x1FFFF) return 0x1FFFF;

    return n;
}

/* Matrix-vector multiplication */
void mulMV(const Matrix &m, const Vec16 &vtx, int shift, bool lm) {
    for (int i = 0; i < 3; i++) setMACIR(i + 1, extsMAC(i + 1, (i64)m[i][X] * (i64)vtx[X] + (i64)m[i][Y] * (i64)vtx[Y] + (i64)m[i][Z] * (i64)vtx[Z]), shift, lm);
}

/* Matrix-vector multiplication with translation */
void mulMVT(const Matrix &m, const Vec16 &vtx, const Vec32 &t, int shift, bool lm) {
    for (int i = 0; i < 3; i++) setMACIR(i + 1, extsMAC(i + 1, extsMAC(i + 1, ((i64)t[i] << 12) + (i64)m[i][X] * (i64)vtx[X]) + (i64)m[i][Y] * (i64)vtx[Y] + (i64)m[i][Z] * (i64)vtx[Z]), shift, lm);
}

/* Color interpolation */
void intCol(i64 mac1, i64 mac2, i64 mac3, int shift, bool lm) {
    setMACIR(1, ((i64)fc[0] << 12) - mac1, shift, lm);
    setMACIR(2, ((i64)fc[1] << 12) - mac2, shift, lm);
    setMACIR(3, ((i64)fc[2] << 12) - mac3, shift, lm);

    setMACIR(1, (i64)ir[1] * (i64)ir[0] + mac1, shift, lm);
    setMACIR(2, (i64)ir[2] * (i64)ir[0] + mac2, shift, lm);
    setMACIR(3, (i64)ir[3] * (i64)ir[0] + mac3, shift, lm);
}

/* Color saturation */
u8 satCol(u32 idx, i32 col) {
    if (col < 0) {
        /* TODO: set flags */

        return 0;
    } else if (col > 0xFF) {
        /* TODO: set flags */

        return 0xFF;
    }

    return (u8)col;
}

/* --- GTE FIFO handlers --- */

i16 getSX(u32 idx) {
    return (i16)sxy[idx];
}

i16 getSY(u32 idx) {
    return (i16)(sxy[idx] >> 16);
}

/* Pushes a color/code */
void pushRGB(u8 *col) {
    /* Advance FIFO stages */
    for (int i = 0; i < 2; i++) rgb[i] = rgb[i + 1];

    rgb[2] = (u32)(col[3] << 24) | ((u32)col[2] << 16) | ((u32)col[1] << 8) | (u32)col[0];
}

/* Pushes screen X and Y values, performs clipping checks */
void pushSXY(i64 x, i64 y) {
    if (x > 1023) {
        x = 1023;
    } else if (x < -1024) {
        x = -1024;
    }

    if (y > 1023) {
        y = 1023;
    } else if (y < -1024) {
        y = -1024;
    }

    /* Advance FIFO stages */
    for (int i = 0; i < 2; i++) sxy[i] = sxy[i + 1];

    sxy[2] = ((u32)(u16)y << 16) | (u32)(u16)x;
}

/* Pushes a screen Z value, performs clipping checks */
void pushSZ(i64 data) {
    if (data < 0) {
        data = 0;
    } else if (data > 0xFFFF) {
        data = 0xFFFF;
    }

    /* Advance FIFO stages */
    for (int i = 0; i < 3; i++) sz[i] = sz[i + 1];

    sz[3] = data;
}

/* AVerage Screen Z (3 values) */
void iAVSZ3() {
    /* Multiply Zs by Z scale factor */

    setMAC(0, (i64)zsf3 * ((i64)sz[1] + (i64)sz[2] + (i64)sz[3]), 0);

    /* Clip and set ordering table Z */

    auto z = mac[0] >> 12;

    if (z > 0xFFFF) {
        z = 0xFFFF;
    } else if (z < 0) {
        z = 0;
    }

    otz = z;

    //std::printf("[GTE:AVSZ3 ] OTZ = 0x%04x\n", otz);
}

/* AVerage Screen Z (4 values) */
void iAVSZ4() {
    /* Multiply Zs by Z scale factor */

    setMAC(0, (i64)zsf4 * ((i64)sz[0] + (i64)sz[1] + (i64)sz[2] + (i64)sz[3]), 0);

    /* Clip and set ordering table Z */

    auto z = mac[0] >> 12;

    if (z > 0xFFFF) {
        z = 0xFFFF;
    } else if (z < 0) {
        z = 0;
    }

    otz = z;

    //std::printf("[GTE:AVSZ4 ] OTZ = 0x%04x\n", otz);
}

/* General purpose interpolation */
void iGPF(u32 cmd) {
    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    for (int i = 1; i < 4; i++) setMACIR(i, (i64)ir[i] * (i64)ir[0], shift, lm);

    /* Calculate and push color/code */

    u8 col[4];

    for (int i = 0; i < 3; i++) col[i] = satCol(i, mac[i + 1] >> 4);

    col[3] = rgbc[3];

    pushRGB(col);

    //std::printf("[GTE:GPF   ] RGB2 = 0x%08x\n", rgb[2]);
}

/* General purpose interpolation with base */
void iGPL(u32 cmd) {
    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    for (int i = 1; i < 4; i++) setMACIR(i, ((i64)ir[i] * (i64)ir[0] + mac[i]) << shift, shift, lm);

    /* Calculate and push color/code */

    u8 col[4];

    for (int i = 0; i < 3; i++) col[i] = satCol(i, mac[i + 1] >> 4);

    col[3] = rgbc[3];

    pushRGB(col);

    //std::printf("[GTE:GPL   ] RGB2 = 0x%08x\n", rgb[2]);
}

/* Vector-matrix multiply with vector add */
void iMVMVA(u32 cmd) {
    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    Matrix m;

    switch ((cmd >> 17) & 3) {
        case 0:
            for (int i = 0; i < 3; i++) {
                m[i][X] = rt[i][X];
                m[i][Y] = rt[i][Y];
                m[i][Z] = rt[i][Z];
            }
            break;
        case 1:
            for (int i = 0; i < 3; i++) {
                m[i][X] = ls[i][X];
                m[i][Y] = ls[i][Y];
                m[i][Z] = ls[i][Z];
            }
            break;
        case 2:
            for (int i = 0; i < 3; i++) {
                m[i][X] = lc[i][X];
                m[i][Y] = lc[i][Y];
                m[i][Z] = lc[i][Z];
            }
            break;
        default:
            std::printf("[GTE:MVMVA ] Unhandled matrix %u\n", (cmd >> 17) & 3);

            exit(0);
    }

    Vec16 vtx;

    switch ((cmd >> 15) & 3) {
        case 0:
            vtx[X] = v[0][X];
            vtx[Y] = v[0][Y];
            vtx[Z] = v[0][Z];
            break;
        case 1:
            vtx[X] = v[1][X];
            vtx[Y] = v[1][Y];
            vtx[Z] = v[1][Z];
            break;
        case 2:
            vtx[X] = v[2][X];
            vtx[Y] = v[2][Y];
            vtx[Z] = v[2][Z];
            break;
        case 3:
            vtx[X] = ir[1];
            vtx[Y] = ir[2];
            vtx[Z] = ir[3];
            break;
    }

    Vec32 vt;

    switch ((cmd >> 13) & 3) {
        case 0:
            vt[X] = tr[X];
            vt[Y] = tr[Y];
            vt[Z] = tr[Z];
            break;
        case 1:
            vt[X] = bk[X];
            vt[Y] = bk[Y];
            vt[Z] = bk[Z];
            break;
        case 2:
            vt[X] = fc[X];
            vt[Y] = fc[Y];
            vt[Z] = fc[Z];
            break;
        case 3:
            vt[X] = 0;
            vt[Y] = 0;
            vt[Z] = 0;
            break;
    }

    mulMVT(m, vtx, vt, shift, lm);
}

/* Normal Color Color(??) Triple */
void iNCCT(u32 cmd) {
    //std::printf("[GTE       ] NCCT\n");

    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    for (int i = 0; i < 3; i++) {
        mulMV(ls, v[i], shift, lm);

        Vec16 vtx = { ir[1], ir[2], ir[3] };

        mulMVT(lc, vtx, bk, shift, lm);

        /* Calculate and push color/code */

        u8 col[4];

        for (int j = 0; j < 3; j++) col[j] = satCol(i, mac[j + 1] >> 4);

        col[3] = rgbc[3];

        pushRGB(col);

        //std::printf("[GTE:NCCT  ] RGB2 = 0x%08x\n", rgb[2]);
    }
}

/* Normal Color Depth cue Single */
void iNCDS(u32 cmd) {
    //std::printf("[GTE       ] NCDS\n");

    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    mulMV(ls, v[0], shift, lm);

    Vec16 vtx = { ir[1], ir[2], ir[3] };

    mulMVT(lc, vtx, bk, shift, lm);

    intCol(((i32)rgbc[0] * (i32)ir[1]) << 4, ((i32)rgbc[1] * (i32)ir[2]) << 4, ((i32)rgbc[2] * (i32)ir[3]) << 4, shift, lm);

    /* Calculate and push color/code */

    u8 col[4];

    for (int i = 0; i < 3; i++) col[i] = satCol(i, mac[i + 1] >> 4);

    col[3] = rgbc[3];

    pushRGB(col);

    //std::printf("[GTE:NCDS  ] RGB2 = 0x%08x\n", rgb[2]);
}

/* Normal CLIPping */
void iNCLIP() {
    //std::printf("[GTE       ] NCLIP\n");

    const auto clip = (i64)getSX(0) * (i64)getSY(1) + (i64)getSX(1) * (i64)getSY(2) + (i64)getSX(2) * (i64)getSY(0) - (i64)getSX(0) * (i64)getSY(2) - (i64)getSX(1) * (i64)getSY(0) - (i64)getSX(2) * (i64)getSY(1);

    setMAC(0, clip, 0);

    //std::printf("[GTE:NCLIP ] MAC0 = 0x%08x\n", mac[0]);
}

/* Rotate/Translate Perspective Single */
void iRTPS(u32 cmd) {
    //std::printf("[GTE       ] RTPS\n");

    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    /* Do perspective transformation on vector Vi */
    const auto x = extsMAC(1, extsMAC(1, 0x1000 * (i64)tr[X] + rt[0][X] * v[0][X]) + rt[0][Y] * v[0][Y] + rt[0][Z] * v[0][Z]);
    const auto y = extsMAC(2, extsMAC(2, 0x1000 * (i64)tr[Y] + rt[1][X] * v[0][X]) + rt[1][Y] * v[0][Y] + rt[1][Z] * v[0][Z]);
    const auto z = extsMAC(3, extsMAC(3, 0x1000 * (i64)tr[Z] + rt[2][X] * v[0][X]) + rt[2][Y] * v[0][Y] + rt[2][Z] * v[0][Z]);

    /* Truncate results to 32 bits */
    setMAC(1, x, shift);
    setMAC(2, y, shift);
    setMAC(3, z, shift);

    setIR(1, mac[1], lm);
    setIR(2, mac[2], lm);

    setIR(3, z >> shift, false);

    /* Push new screen Z */

    pushSZ(mac[3] >> (12 * !sf));

    //std::printf("[GTE:RTPS  ] SZ = 0x%04x\n", sz[3]);

    /* Calculate and push new screen XY */

    //const auto unr = (i64)div(h, sz[3]);
    const auto unr = ((0x10000 * h) + (sz[3] >> 1)) / sz[3];

    const auto sx = unr * (i64)ir[1] + (i64)ofx;
    const auto sy = unr * (i64)ir[2] + (i64)ofy;

    pushSXY(sx >> 16, sy >> 16);

    //std::printf("[GTE:RTPS  ] SXY = 0x%08x\n", sxy[2]);

    /* TODO: check for SX/SY MAC overflow */

    /* Depth cue */

    const auto dc = unr * (i64)dca + (i64)dcb;

    setMAC(0, dc, 0);

    setIR(0, dc >> 12, true);

    //std::printf("[GTE:RTPS  ] IR0 = 0x%04x\n", ir[0]);
}

/* Rotate/Translate Perspective Triple */
void iRTPT(u32 cmd) {
    //std::printf("[GTE       ] RTPT\n");

    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    for (int i = 0; i < 3; i++) {
        /* Do perspective transformation on vector Vi */
        const auto x = extsMAC(1, extsMAC(1, 0x1000 * (i64)tr[X] + rt[0][X] * v[i][X]) + rt[0][Y] * v[i][Y] + rt[0][Z] * v[i][Z]);
        const auto y = extsMAC(2, extsMAC(2, 0x1000 * (i64)tr[Y] + rt[1][X] * v[i][X]) + rt[1][Y] * v[i][Y] + rt[1][Z] * v[i][Z]);
        const auto z = extsMAC(3, extsMAC(3, 0x1000 * (i64)tr[Z] + rt[2][X] * v[i][X]) + rt[2][Y] * v[i][Y] + rt[2][Z] * v[i][Z]);

        /* Truncate results to 32 bits */
        setMAC(1, x, shift);
        setMAC(2, y, shift);
        setMAC(3, z, shift);

        setIR(1, mac[1], lm);
        setIR(2, mac[2], lm);

        setIR(3, z >> shift, false);

        /* Push new screen Z */

        pushSZ(mac[3] >> (12 * !sf));

        //std::printf("[GTE:RTPT  ] SZ = 0x%04x\n", sz[3]);

        /* Calculate and push new screen XY */

        //const auto unr = (i64)div(h, sz[3]);
        const auto unr = ((0x10000 * h) + (sz[3] >> 1)) / sz[3];

        const auto sx = unr * (i64)ir[1] + (i64)ofx;
        const auto sy = unr * (i64)ir[2] + (i64)ofy;

        pushSXY(sx >> 16, sy >> 16);

        //std::printf("[GTE:RTPT  ] SXY = 0x%08x\n", sxy[2]);

        /* TODO: check for SX/SY MAC overflow */

        /* Depth cue */

        const auto dc = unr * (i64)dca + (i64)dcb;

        setMAC(0, dc, 0);

        setIR(0, dc >> 12, true);

        //std::printf("[GTE:RTPT  ] IR0 = 0x%04x\n", ir[0]);
    }
}

/* SQuare Root */
void iSQR(u32 cmd) {
    const bool lm = cmd & (1 << 10);
    const bool sf = cmd & (1 << 19);
    
    const auto shift = 12 * sf;

    for (int i = 1; i < 4; i++) mac[i] = ((i32)ir[i] * (i32)ir[i]) >> shift;
    for (int i = 1; i < 4; i++) setIR(i, mac[i], lm);
}

void doCmd(u32 cmd) {
    const auto opcode = cmd & 0x3F;

    switch (opcode) {
        case Opcode::RTPS : iRTPS(cmd); break;
        case Opcode::NCLIP: iNCLIP(); break;
        case Opcode::MVMVA: iMVMVA(cmd); break;
        case Opcode::NCDS : iNCDS(cmd); break;
        case Opcode::SQR  : iSQR(cmd); break;
        case Opcode::AVSZ3: iAVSZ3(); break;
        case Opcode::AVSZ4: iAVSZ4(); break;
        case Opcode::RTPT : iRTPT(cmd); break;
        case Opcode::GPF  : iGPF(cmd); break;
        case Opcode::GPL  : iGPL(cmd); break;
        case Opcode::NCCT : iNCCT(cmd); break;
        default:
            std::printf("[GTE       ] Unhandled instruction 0x%02X (0x%07X)\n", opcode, cmd);

            exit(0);
    }
}

}
