//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cop0.zig - EmotionEngine Core COP0
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const exts = @import("../common/extend.zig").exts;

/// COP0 register aliases
pub const Cop0Reg = enum(u32) {
    Index       =  0,
    Random      =  1,
    EntryLo0    =  2,
    EntryLo1    =  3,
    Context     =  4,
    PageMask    =  5,
    Wired       =  6,
    R7          =  7,
    BadVAddr    =  8,
    Count       =  9,
    EntryHi     = 10,
    Compare     = 11,
    Status      = 12,
    Cause       = 13,
    EPC         = 14,
    PRId        = 15,
    Config      = 16,
    LLAddr      = 17,
    WatchLo     = 18,
    WatchHi     = 19,
    XContext    = 20,
    R21         = 21,
    R22         = 22,
    R23         = 23,
    R24         = 24,
    R25         = 25,
    ParityError = 26,
    CacheError  = 27,
    TagLo       = 28,
    TagHi       = 29,
    ErrorEPC    = 30,
    R31         = 31,
};

/// COP0 Config register
const Config = struct {
     k0: u3   = undefined, // KSEG0 cache mode
    bpe: bool = false,     // Branch Prediction Enable
    nbe: bool = false,     // Non-Blocking load Enable
    dce: bool = false,     // Data Cache Enable
    ice: bool = false,     // Instruction Cache Enable
    die: bool = false,     // Double Issue Enable

    /// Returns Config
    pub fn get(self: Config) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.k0);
        data |= 1 << 6; // Data Cache size
        data |= 2 << 9; // Instruction Cache size
        data |= @as(u32, @bitCast(u1, self.bpe)) << 12;
        data |= @as(u32, @bitCast(u1, self.nbe)) << 13;
        data |= @as(u32, @bitCast(u1, self.dce)) << 16;
        data |= @as(u32, @bitCast(u1, self.ice)) << 17;
        data |= @as(u32, @bitCast(u1, self.die)) << 18;

        return data;
    }

    /// Sets Config
    pub fn set(self: *Config, data: u32) void {
        self.k0  = @truncate(u3, data);
        self.bpe = (data & (1 << 12)) != 0;
        self.nbe = (data & (1 << 13)) != 0;
        self.dce = (data & (1 << 16)) != 0;
        self.ice = (data & (1 << 17)) != 0;
        self.die = (data & (1 << 18)) != 0;
    }
};

/// COP0 Status register
const Status = struct {
    ie : bool = undefined, // Interrupt Enable
    exl: bool = undefined, // EXception Level
    erl: bool = true,      // ERror Level
    ksu: u2   = 0,         // Kernel/Supervisor/User mode
    bem: bool = undefined, // Bus Error Mask
     im: u3   = undefined, // Interrupt Mask
    eie: bool = undefined, // Enable IE bit
    edi: bool = undefined, // Enable EI/DI
     ch: bool = undefined, // Cache Hit
    bev: bool = true,      // Boot Exception Vector
    dev: bool = undefined, // Debug Exception Vector
     cu: u4   = undefined, // Coprocessor Usable

    // Returns Status
    pub fn get(self: Status) u32 {
        var data: u32 = 0;

        data |= @as(u32, @bitCast(u1, self.ie ));
        data |= @as(u32, @bitCast(u1, self.exl)) << 1;
        data |= @as(u32, @bitCast(u1, self.erl)) << 2;
        data |= @as(u32, self.ksu) << 3;
        data |= @as(u32, self.im & 3) << 10;
        data |= @as(u32, @bitCast(u1, self.bem)) << 12;
        data |= @as(u32, self.im & 4) << 13;
        data |= @as(u32, @bitCast(u1, self.eie)) << 16;
        data |= @as(u32, @bitCast(u1, self.edi)) << 17;
        data |= @as(u32, @bitCast(u1, self.ch )) << 18;
        data |= @as(u32, @bitCast(u1, self.bev)) << 22;
        data |= @as(u32, @bitCast(u1, self.dev)) << 23;
        data |= @as(u32, self.cu) << 28;

        return data;
    }

    /// Sets Status
    pub fn set(self: *Status, data: u32) void {
        self.ie  = (data & 1) != 0;
        self.exl = (data & (1 << 1)) != 0;
        self.erl = (data & (1 << 2)) != 0;
        self.ksu = @truncate(u2, data >> 3);
        self.im  = @truncate(u3, (data >> 10) & 3);
        self.bem = (data & (1 << 12)) != 0;
        self.im |= @truncate(u3, (data >> 13) & 4);
        self.eie = (data & (1 << 16)) != 0;
        self.edi = (data & (1 << 17)) != 0;
        self.ch  = (data & (1 << 18)) != 0;
        self.bev = (data & (1 << 22)) != 0;
        self.dev = (data & (1 << 23)) != 0;
        self.cu  = @truncate(u4, data >> 28);
    }
};

/// COP0 register file (private)
var compare: u32 = undefined;
var   count: u32 = undefined;

var config: Config = Config{};
var status: Status = Status{};

/// Initializes the COP0 module
pub fn init() void {}

/// Returns a COP0 register
pub fn get(comptime T: type, idx: u5) T {
    assert(T == u32 or T == u64);

    var data: T = undefined;

    switch (idx) {
        @enumToInt(Cop0Reg.PRId) => data = @as(T, 0x59),
        else => {
            err("  [COP0 (EE) ] Unhandled register read ({s}) @ {s}.", .{@typeName(T), @tagName(@intToEnum(Cop0Reg, idx))});

            assert(false);
        }
    }

    return data;
}

/// Sets a COP0 register
pub fn set(comptime T: type, idx: u5, data: T) void {
    assert(T == u32 or T == u64);

    switch (idx) {
        @enumToInt(Cop0Reg.Count  ) => count   = data,
        @enumToInt(Cop0Reg.Compare) => compare = data,
        @enumToInt(Cop0Reg.Status ) => status.set(data),
        @enumToInt(Cop0Reg.Config ) => config.set(data),
        else => {
            err("  [COP0 (EE) ] Unhandled register write ({s}) @ {s} = 0x{X:0>8}.", .{@typeName(T), @tagName(@intToEnum(Cop0Reg, idx)), data});

            assert(false);
        }
    }
}
