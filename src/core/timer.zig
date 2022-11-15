//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! timer.zig - Timer module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

/// Timer registers
const TimerReg = enum(u32) {
    TCount = 0x1000_0000,
    TMode  = 0x1000_0010,
    TComp  = 0x1000_0020,
    THold  = 0x1000_0030,
};

/// Writes data to Timer I/O
pub fn write(addr: u32, data: u32) void {
    const chn = @truncate(u2, addr >> 11);

    switch (addr & ~@as(u32, 0x1800)) {
        @enumToInt(TimerReg.TCount) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_COUNT) = 0x{X:0>8}.", .{addr, chn, data});
        },
        @enumToInt(TimerReg.TMode) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_MODE) = 0x{X:0>8}.", .{addr, chn, data});
        },
        @enumToInt(TimerReg.TComp) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_COMP) = 0x{X:0>8}.", .{addr, chn, data});
        },
        @enumToInt(TimerReg.THold) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_HOLD) = 0x{X:0>8}.", .{addr, chn, data});
        },
        else => {
            err("  [Timer     ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});
        }
    }
}
