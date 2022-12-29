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

const intc = @import("intc.zig");

const IntSource = intc.IntSource;

/// Timer registers
const TimerReg = enum(u32) {
    TCount = 0x1000_0000,
    TMode  = 0x1000_0010,
    TComp  = 0x1000_0020,
    THold  = 0x1000_0030,
};

/// Timer mode
const TimerMode = struct {
    clks: u2   = undefined,
    gate: bool = undefined,
    gats: bool = undefined,
    gatm: u2   = undefined,
    zret: bool = undefined,
     cue: bool = undefined,
    cmpe: bool = undefined,
    ovfe: bool = undefined,
    equf: bool = undefined,
    ovff: bool = undefined,

    /// Returns the timer mode register
    pub fn get(self: TimerMode) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.clks);
        data |= @as(u32, @bitCast(u1, self.gate)) << 2;
        data |= @as(u32, @bitCast(u1, self.gats)) << 3;
        data |= @as(u32, self.gatm) << 4;
        data |= @as(u32, @bitCast(u1, self.zret)) <<  6;
        data |= @as(u32, @bitCast(u1, self.cue )) <<  7;
        data |= @as(u32, @bitCast(u1, self.cmpe)) <<  8;
        data |= @as(u32, @bitCast(u1, self.ovfe)) <<  9;
        data |= @as(u32, @bitCast(u1, self.equf)) << 10;
        data |= @as(u32, @bitCast(u1, self.ovff)) << 11;

        return data;
    }

    /// Sets the timer mode
    pub fn set(self: *TimerMode, data: u32) void {
        self.clks = @truncate(u2, data);
        self.gate = (data & (1 << 2)) != 0;
        self.gats = (data & (1 << 3)) != 0;
        self.gatm = @truncate(u2, data >> 4);
        self.zret = (data & (1 << 6)) != 0;
        self.cue  = (data & (1 << 7)) != 0;
        self.cmpe = (data & (1 << 8)) != 0;
        self.ovfe = (data & (1 << 9)) != 0;

        if ((data & (1 << 10)) != 0) {
            self.equf = false;
        }
        if ((data & (1 << 11)) != 0) {
            self.ovff = false;
        }
    }
};

/// EE timer
const Timer = struct {
    count: u16 = 0,
     mode: TimerMode = undefined,
     comp: u16 = 0,
     hold: u16 = 0,
};

var timers: [4]Timer = undefined;

/// Read data from Timer I/O
pub fn read(addr: u32) u32 {
    var data: u32 = undefined;

    const chn = @truncate(u2, addr >> 11);

    switch (addr & ~@as(u32, 0x1800)) {
        @enumToInt(TimerReg.TCount) => {
            info("   [Timer     ] Read @ 0x{X:0>8} (T{}_COUNT).", .{addr, chn});

            data = timers[chn].count;
        },
        @enumToInt(TimerReg.TMode) => {
            info("   [Timer     ] Read @ 0x{X:0>8} (T{}_MODE).", .{addr, chn});

            data = timers[chn].mode.get();
        },
        @enumToInt(TimerReg.TComp) => {
            info("   [Timer     ] Read @ 0x{X:0>8} (T{}_COMP).", .{addr, chn});

            data = timers[chn].comp;
        },
        @enumToInt(TimerReg.THold) => {
            info("   [Timer     ] Read @ 0x{X:0>8} (T{}_HOLD).", .{addr, chn});

            data = timers[chn].hold;
        },
        else => {
            err("  [Timer     ] Unhandled read @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }

    return data;
}

/// Writes data to Timer I/O
pub fn write(addr: u32, data: u32) void {
    const chn = @truncate(u2, addr >> 11);

    switch (addr & ~@as(u32, 0x1800)) {
        @enumToInt(TimerReg.TCount) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_COUNT) = 0x{X:0>8}.", .{addr, chn, data});

            timers[chn].count = @truncate(u16, data);
        },
        @enumToInt(TimerReg.TMode) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_MODE) = 0x{X:0>8}.", .{addr, chn, data});
            
            timers[chn].mode.set(@truncate(u16, data));
        },
        @enumToInt(TimerReg.TComp) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_COMP) = 0x{X:0>8}.", .{addr, chn, data});

            timers[chn].comp = @truncate(u16, data);
        },
        @enumToInt(TimerReg.THold) => {
            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_HOLD) = 0x{X:0>8}.", .{addr, chn, data});

            timers[chn].hold = @truncate(u16, data);
        },
        else => {
            err("  [Timer     ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});
        }
    }
}

/// Steps HBLANK timers
pub fn stepHblank() void {
    var i: u3 = 0;
    while (i < 4) : (i += 1) {
        if (timers[i].mode.clks != 3) continue;

        const oldCount = timers[i].count;

        timers[i].count +%= 1;

        if (timers[i].count == timers[i].comp) {
            if (timers[i].mode.cmpe and !timers[i].mode.equf) {
                timers[i].mode.equf = true;

                sendInterrupt(i);
            }

            if (timers[i].mode.zret) {
                timers[i].count = 0;
            }
        } else if (oldCount == 0xFFFF) {
            if (timers[i].mode.ovfe and !timers[i].mode.ovff) {
                timers[i].mode.ovff = true;

                sendInterrupt(i);
            }
        }
    }
}

/// Sends an interrupt request to INTC
fn sendInterrupt(tmId: u3) void {
    const intSource = @intToEnum(IntSource, @as(u4, tmId) + 9);
    
    intc.sendInterrupt(intSource);
}
