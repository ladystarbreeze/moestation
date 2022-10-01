//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! extend.zig - Sign-extension helpers
//!

const std = @import("std");

const assert = std.debug.assert;

pub fn exts(comptime dstT: type, comptime srcT: type, data: srcT) dstT {
    assert(srcT == u8  or srcT == u16 or srcT == u32);
    assert(dstT == u32 or dstT == u64);
 
    var temp: u64 = undefined;

    switch (srcT) {
        u8  => temp = @bitCast(u64, @as(i64, @bitCast(i8, data))),
        u16 => temp = @bitCast(u64, @as(i64, @bitCast(i16, data))),
        u32 => temp = @bitCast(u64, @as(i64, @bitCast(i32, data))),
    }

    return @truncate(dstT, temp);
}
