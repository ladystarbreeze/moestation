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
var intcMask: u15 = 0;
var intcStat: u15 = 0;

/// Returns INTC_MASK
pub fn getMask() u32 {
    return @as(u32, intcMask);
}

/// Returns INTC_STAT
pub fn getStat() u32 {
    return @as(u32, intcStat);
}

/// Sets INTC_MASK, checks for interrupt
pub fn setMask(data: u32) void {
    intcMask = @truncate(u15, data);

    // TODO: Check for interrupts
}

/// Sets INTC_STAT, checks for interrupt
pub fn setStat(data: u32) void {
    intcStat &= ~@truncate(u15, data);

    // TODO: Check for interrupts
}
