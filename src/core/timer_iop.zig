//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! timer_iop.zig - IOP timer module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const intc = @import("intc.zig");

const IntSourceIop = intc.IntSourceIop;

/// IOP timer registers
const TimerReg = enum(u32) {
    TCount = 0x1F80_1100,
    TMode  = 0x1F80_1104,
    TComp  = 0x1F80_1108,
};

/// Timer mode register
const TimerMode = struct {
    gate: bool = undefined, // GATE enable
    gats: u2   = undefined, // GATe Select
    zret: bool = undefined, // Zero RETurn
    cmpe: bool = undefined, // CoMPare Enabled
    ovfe: bool = undefined, // OVerFlow Enabled
    rept: bool = undefined, // REPeaT interrupt
    levl: bool = undefined, // LEVL
    clks: bool = undefined, // CLocK Select
    pre2: bool = undefined, // Timer 2 PREscaler
    intf: bool = undefined, // INTerrupt Flag
    equf: bool = undefined, // EQUal Flag
    ovff: bool = undefined, // OVerFlow Flag
    pre4: u2   = undefined, // Timer 4/5 PREscaler
    
    /// Return T_MODE
    pub fn get(self: *TimerMode) u16 {
        var data: u16 = 0;

        data |= @as(u16, @bitCast(u1, self.gate));
        data |= @as(u16, self.gats) << 1;
        data |= @as(u16, @bitCast(u1, self.zret)) << 3;
        data |= @as(u16, @bitCast(u1, self.cmpe)) << 4;
        data |= @as(u16, @bitCast(u1, self.ovfe)) << 5;
        data |= @as(u16, @bitCast(u1, self.rept)) << 6;
        data |= @as(u16, @bitCast(u1, self.levl)) << 7;
        data |= @as(u16, @bitCast(u1, self.clks)) << 8;
        data |= @as(u16, @bitCast(u1, self.pre2)) << 9;
        data |= @as(u16, @bitCast(u1, self.intf)) << 10;
        data |= @as(u16, @bitCast(u1, self.equf)) << 11;
        data |= @as(u16, @bitCast(u1, self.ovff)) << 12;
        data |= @as(u16, self.pre4) << 13;

        self.equf = false;
        self.ovff = false;

        return data;
    }

    /// Sets T_MODE
    pub fn set(self: *TimerMode, data: u16) void {
        self.gate = (data & 1) != 0;
        self.gats = @truncate(u2, data >> 1);
        self.zret = (data & (1 << 3)) != 0;
        self.cmpe = (data & (1 << 4)) != 0;
        self.ovfe = (data & (1 << 5)) != 0;
        self.rept = (data & (1 << 6)) != 0;
        self.levl = (data & (1 << 7)) != 0;
        self.clks = (data & (1 << 8)) != 0;
        self.pre2 = (data & (1 << 9)) != 0;
        self.pre4 = @truncate(u2, data >> 13);

        self.intf = true;
    }
};

/// IOP timer
const Timer = struct {
    count: u32       = undefined,
     mode: TimerMode = undefined,
     comp: u32       = undefined,
    scale: u32       = undefined,
};

var timers: [6]Timer = undefined;

/// Get timer ID
fn getTimer(addr: u8) u3 {
    var tmId: u3 = undefined;

    switch (addr) {
        0x10 => tmId = 0,
        0x11 => tmId = 1,
        0x12 => tmId = 2,
        0x48 => tmId = 3,
        0x49 => tmId = 4,
        0x4A => tmId = 5,
        else => {
            err("  [Timer     ] Unhandled timer 0x{X:0>2}.", .{addr});

            assert(false);
        }
    }

    return tmId;
}

/// Returns timer register
pub fn read(comptime T: type, addr: u32) T {
    var data: T = undefined;

    const tmId = getTimer(@truncate(u8, addr >> 4));

    switch (addr & ~@as(u32, 0xFF0) | 0x100) {
        @enumToInt(TimerReg.TCount) => {
            if (T != u16 and T != u32) {
                @panic("Unhandled read @ Timer I/O");
            }

            info("   [Timer     ] Read ({s}) @ 0x{X:0>8} (T{}_COUNT) = 0x{X:0>8} (COMP = 0x{X:0>8}).", .{@typeName(T), addr, tmId, timers[tmId].count, timers[tmId].comp});

            if (T == u16) {
                data = @truncate(u16, timers[tmId].count >> @truncate(u5, 16 * ((addr >> 1) & 1)));
            } else {
                data = timers[tmId].count;
            }
        },
        @enumToInt(TimerReg.TMode) => {
            if (T != u16) {
                @panic("Unhandled read @ Timer I/O");
            }

            info("   [Timer     ] Read @ 0x{X:0>8} (T{}_MODE).", .{addr, tmId});

            data = timers[tmId].mode.get();
        },
        else => {
            err("  [Timer     ] Unhandled read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

            assert(false);
        }
    }

    return data;
}

/// Writes timer register
pub fn write(comptime T: type, addr: u32, data: T) void {
    const tmId = getTimer(@truncate(u8, addr >> 4));

    switch (addr & ~@as(u32, 0xFF0) | 0x100) {
        @enumToInt(TimerReg.TCount) => {
            if (!(T == u16 or T == u32)) {
                @panic("Unhandled write @ Timer I/O");
            }

            if ((addr & 2) != 0) {
                @panic("Unhandled write @ Timer I/O");
            }

            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_COUNT) = 0x{X:0>4}.", .{addr, tmId, data});

            timers[tmId].count = @as(u32, data);
        },
        @enumToInt(TimerReg.TMode) => {
            if (T != u16) {
                @panic("Unhandled write @ Timer I/O");
            }

            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_MODE) = 0x{X:0>4}.", .{addr, tmId, data});

            timers[tmId].mode.set(data);

            timers[tmId].count = 0;
        },
        @enumToInt(TimerReg.TComp) => {
            if (!(T == u16 or T == u32)) {
                @panic("Unhandled write @ Timer I/O");
            }

            if ((addr & 2) != 0) {
                @panic("Unhandled write @ Timer I/O");
            }

            info("   [Timer     ] Write @ 0x{X:0>8} (T{}_COMP) = 0x{X:0>4}.", .{addr, tmId, data});

            timers[tmId].comp = @as(u32, data);

            if (!timers[tmId].mode.levl) timers[tmId].mode.intf = true;
        },
        else => {
            err("  [Timer     ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X:0>8}.", .{@typeName(T), addr, data});

            assert(false);
        }
    }
}

/// Increments HBLANK timers
pub fn stepHblank() void {
    var i: u3 = 1;
    while (i < 4) : (i += 2) {
        if (!timers[i].mode.clks) continue;

        const oldCount = timers[i].count;

        timers[i].count +%= 1;

        if (i == 1) {
            timers[i].count &= 0xFFFF;
        }

        if (timers[i].count == timers[i].comp) {
            if (timers[i].mode.cmpe) {
                timers[i].mode.equf = true;

                sendInterrupt(i);

                if (timers[i].mode.zret) {
                    timers[i].count = 0;
                }
            }
        } else if ((i < 3 and oldCount == 0xFFFF) or (i >= 3 and oldCount == @bitCast(u32, @as(i32, -1)))) {
            if (timers[i].mode.ovfe) {
                timers[i].mode.ovff = true;
                
                sendInterrupt(i);
            }
        }
    }
}

/// Increments IOP timers, checks for interrupts
pub fn step() void {
    var i: u3 = 0;
    while (i < 6) : (i += 1) {
        if (timers[i].mode.gate) {
            err("  [Timer     ] Unhandled gate function.", .{});
            
            assert(false);
        }

        if (!(i == 1 or i == 3) and timers[i].mode.clks) {
            err("  [Timer     ] Unhandled Timer {} external clock.", .{i});
            
            assert(false);
        }

        if (i == 2 and timers[i].mode.pre2) {
            err("  [Timer     ] Unhandled Timer 2 prescaler.", .{});
        
            assert(false);
        }

        if (i >= 4 and timers[i].mode.pre4 != 0) {
            err("  [Timer     ] Unhandled Timer {} prescaler.", .{i});
        
            assert(false);
        }

        const oldCount = timers[i].count;

        timers[i].count +%= 1;

        if (i < 3) {
            timers[i].count &= 0xFFFF;
        }

        if (timers[i].count == timers[i].comp) {
            if (timers[i].mode.cmpe) {
                timers[i].mode.equf = true;

                sendInterrupt(i);

                // TODO: no zero return is a hack! Fix this!
                if (timers[i].mode.zret) {
                    timers[i].count = 0;
                }
            }
        } else if ((i < 3 and oldCount == 0xFFFF) or (i >= 3 and oldCount == @bitCast(u32, @as(i32, -1)))) {
            if (timers[i].mode.ovfe) {
                timers[i].mode.ovff = true;
                
                sendInterrupt(i);
            }
        }
    }
}

/// Sends an interrupt request to INTC
fn sendInterrupt(tmId: u3) void {
    if (timers[tmId].mode.intf) {
        const intSource = if (tmId < 3) @intToEnum(IntSourceIop, @as(u5, tmId) + 4) else @intToEnum(IntSourceIop, @as(u5, tmId) + 11);

        intc.sendInterruptIop(intSource);
    }

    if (timers[tmId].mode.rept and timers[tmId].mode.levl) {
        timers[tmId].mode.intf = !timers[tmId].mode.intf;
    } else {
        timers[tmId].mode.intf = false;
    }
}
