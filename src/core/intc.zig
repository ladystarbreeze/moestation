//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! intc.zig - Interrupt controller
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

/// Interrupt sources
const IntSource = enum(u4) {
    Gs,
    Sbus,
    VblankStart,
    VblankEnd,
    Vif0,
    Vif1,
    Vu0,
    Vu1,
    Ipu,
    Timer0,
    Timer1,
    Timer2,
    Timer3,
    Sfifo,
    Vu0Watchdog,
};

// INTC registers
var intcMask: u15 = undefined;
var intcStat: u15 = undefined;

// INTC registers (IOP)
var iStat: u25  = undefined;
var iMask: u25  = undefined;
var iCtrl: bool = undefined;

/// Returns I_CTRL
pub fn getCtrl() u32 {
    return @as(u32, @bitCast(u1, iCtrl));
}

/// Returns INTC_MASK
pub fn getMask() u32 {
    return @as(u32, intcMask);
}

/// Returns I_MASK
pub fn getMaskIop(comptime T: type, offset: u2) T {
    var data: T = undefined;

    switch (T) {
        u8  => assert(false),
        u16 => {
            if ((offset & 1) == 0) {
                data = @truncate(u16, iMask);
            } else {
                data = @truncate(u16, iMask >> 16);
            }
        },
        u32 => data = @as(u32, iMask),
        else => unreachable,
    }

    return data;
}

/// Returns INTC_STAT
pub fn getStat() u32 {
    return @as(u32, intcStat);
}

/// Returns I_STAT
pub fn getStatIop() u32 {
    return @as(u32, iStat);
}

/// Sets INTC_MASK, checks for interrupt
pub fn setMask(data: u32) void {
    intcMask = @truncate(u15, data);

    checkInterrupt();
}

/// Sets I_MASK, checks for interrupt
pub fn setMaskIop(comptime T: type, data: T, offset: u2) void {
    switch (T) {
        u8  => assert(false),
        u16 => {
            if ((offset & 1) == 0) {
                iMask = (iMask & 0x1F_0000) | @as(u25, data);
            } else {
                iMask = (@as(u25, data) << 16) | (iMask & 0xFFFF);
            }
        },
        u32 => iMask = @truncate(u25, data),
        else => unreachable,
    }

    checkInterruptIop();
}

/// Sets INTC_STAT, checks for interrupt
pub fn setStat(data: u32) void {
    intcStat &= ~@truncate(u15, data);

    checkInterrupt();
}

/// Sets I_STAT, checks for interrupt
pub fn setStatIop(comptime T: type, data: T, offset: u2) void {
    switch (T) {
        u8  => assert(false),
        u16 => {
            if ((offset & 1) == 0) {
                iStat &= ~@as(u25, data);
            } else {
                iStat &= ~@as(u25, data) << 16;
            }
        },
        u32 => iStat = ~@truncate(u25, data),
        else => unreachable,
    }

    checkInterruptIop();
}

fn checkInterrupt() void {
    if ((intcStat & intcMask) != 0) {
        err("  [INTC      ] Unhandled EE interrupt.", .{});

        assert(false);
    }
}

fn checkInterruptIop() void {
    if (iCtrl and ((iStat & iMask) != 0)) {
        err("  [INTC      ] Unhandled IOP interrupt.", .{});

        assert(false);
    }
}
