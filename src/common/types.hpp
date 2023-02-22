/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once

#include <cinttypes>

using u8   = std::uint8_t;
using u16  = std::uint16_t;
using u32  = std::uint32_t;
using u64  = std::uint64_t;

using i8   = std::int8_t;
using i16  = std::int16_t;
using i32  = std::int32_t;
using i64  = std::int64_t;

/* --- 128-bit integer types --- */

/*
 * The following integer definitions have been taken from PCSX2 and slightly modified, all credits go to the PCSX2 team.
 * https://github.com/PCSX2/pcsx2/blob/bb7ff414aec4113e836c4415a20e7937f11dd952/common/Pcsx2Types.h#L39
 */

/* Unsigned 128-bit integer */
union u128 {
    struct {
        u64 lo;
        u64 hi;
    };

    u64 _u64[2];
    u32 _u32[4];
    u16 _u16[8];
    u8  _u8[8];

    /* Conversion from u64 (zero-extended) */
    static u128 from64(u64 src) {
        u128 data;

        data.lo = src;
        data.hi = 0;

        return data;
    }

    /* Conversion from u32 (zero-extended) */
    static u128 from32(u64 src) {
        u128 data;

        data._u32[0] = src;
        data._u32[1] = 0;

        data.hi = 0;

        return data;
    }

    operator u32() const { return _u32[0]; }
    operator u16() const { return _u16[0]; }
    operator u8()  const { return _u8[0]; }

    bool operator==(const u128 &rhs) const {
        return (lo == rhs.lo) && (hi == rhs.hi);
    }

    bool operator!=(const u128 &rhs) const {
        return (lo != rhs.lo)|| (hi != rhs.hi);
    }
};

/* Signed 128-bit integer */
struct i128 {
    i64 lo;
    i64 hi;

    /* Conversion from i64 (sign-extended) */
    static i128 from64(i64 src) {
        i128 data = {src, (src < 0) ? -1 : 0};

        return data;
    }

    /* Conversion from i32 (sign-extended) */
    static i128 from32(i32 src) {
        i128 data = {src, (src < 0) ? -1 : 0};

        return data;
    }

    operator u32() const { return (i32)lo; }
    operator u16() const { return (i16)lo; }
    operator u8()  const { return (i8)lo; }

    bool operator==(const i128 &rhs) const {
        return (lo == rhs.lo) && (hi == rhs.hi);
    }

    bool operator!=(const i128 &rhs) const {
        return (lo != rhs.lo)|| (hi != rhs.hi);
    }
};
