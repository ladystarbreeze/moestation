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

const iop = @import("iop.zig");

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

pub const IntSourceIop = enum(u5) {
    VblankStart,
    Gpu,
    Cdvd,
    Dma,
    Timer0,
    Timer1,
    Timer2,
    Sio0,
    Sio1,
    Spu2,
    Pio,
    VblankEnd,
    Dvd,
    Pcmcia,
    Timer3,
    Timer4,
    Timer5,
    Sio2,
    Htr0,
    Htr1,
    Htr2,
    Htr3,
    Usb,
    Extr,
    Fwre,
    Fdma,
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

/// Sets I_CTRL
pub fn setCtrl(data: u32) void {
    iCtrl = (data & 1) != 0;

    checkInterrupt();
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
                iStat &= ~@as(u25, data & 0xFFFF);
            } else {
                iStat &= ~(@as(u25, (data & 0xFFFF)) << 16);
            }
        },
        u32 => iStat = ~@truncate(u25, data),
        else => unreachable,
    }

    checkInterruptIop();
}

/// Sends an IOP interrupt request
pub fn sendInterruptIop(src: IntSourceIop) void {
    info("   [INTC (IOP)] {s} interrupt request.", .{@tagName(src)});

    iStat |= @as(u25, 1) << @enumToInt(src);

    checkInterruptIop();
}

fn checkInterrupt() void {
    if ((intcStat & intcMask) != 0) {
        err("  [INTC      ] Unhandled EE interrupt.", .{});

        assert(false);
    }
}

fn checkInterruptIop() void {
    info("   [INTC (IOP)] I_CTRL = {}, I_STAT = 0b{b:0>25}, I_MASK = 0b{b:0>25}", .{iCtrl, iStat, iMask});

    iop.setIntPending(iCtrl and ((iStat & iMask) != 0));
}
