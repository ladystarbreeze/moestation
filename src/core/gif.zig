//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! gif.zig - Graphics Interface
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

/// GIF I/O
const GifReg = enum(u32) {
    GifCtrl  = 0x1000_3000,
    GifMode  = 0x1000_3010,
    GifStat  = 0x1000_3020,
    GifTag0  = 0x1000_3040,
    GifTag1  = 0x1000_3050,
    GifTag2  = 0x1000_3060,
    GifTag3  = 0x1000_3070,
    GifCnt   = 0x1000_3080,
    GifP3Cnt = 0x1000_3090,
    GifP3Tag = 0x1000_30A0,
};

/// Reads data from GIF I/O
pub fn read(addr: u32) u32 {
    var data: u32 = 0;

    switch (addr) {
        @enumToInt(GifReg.GifStat) => {
            info("   [GIF       ] Read @ 0x{X:0>8} (GIF_STAT).", .{addr});
        },
        else => {
            err("  [GIF       ] Unhandled read @ 0x{X:0>8}.", .{addr});

            assert(false);
        }
    }

    return data;
}

/// Writes data to GIF I/O
pub fn write(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(GifReg.GifCtrl) => {
            info("   [GIF       ] Write @ 0x{X:0>8} (GIF_CTRL) = 0x{X:0>8}.", .{addr, data});

            if ((data & 1) != 0) {
                info("   [GIF       ] Resetting GIF.", .{});
            }
        },
        else => {
            err("  [GIF       ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }
}

/// Writes data to GIF FIFO
pub fn writeFifo(data: u128) void {
    info("   [GIF       ] Write @ FIFO = 0x{X:0>32}.", .{data});
}
