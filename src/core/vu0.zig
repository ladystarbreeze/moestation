//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! vu0.zig - Vector Unit 0 module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

/// Macro mode control registers
const ControlReg = enum(u5) {
    Fbrst = 28,
};

/// VU0 register file
const RegFile = struct {
    vi: [16]u16 = undefined,

    /// Returns a VI register
    pub fn getVi(self: RegFile, idx: u4) u16 {
        return self.vi[idx];
    }
};

var regFile: RegFile = RegFile{};

/// Returns a COP2 control register
pub fn getControl(comptime T: type, idx: u5) T {
    var data: T = undefined;

    switch (idx) {
        0 ... 15 => {
            info("   [VU0 (COP2)] Control register read ({s}) @ $VI{}.", .{@typeName(T), idx});

            data = @as(T, regFile.getVi(@truncate(u4, idx)));
        },
        @enumToInt(ControlReg.Fbrst) => {
            info("   [VU0 (COP2)] Control register read ({s}) @ $FBRST.", .{@typeName(T)});

            data = 0;
        },
        else => {
            err("  [VU0 (COP2)] Unhandled control register read ({s}) @ ${}.", .{@typeName(T), idx});

            assert(false);
        }
    }

    return data;
}

/// Sets a COP2 control register
pub fn setControl(comptime T: type, idx: u5, data: T) void {
    switch (idx) {
        @enumToInt(ControlReg.Fbrst) => {
            info("   [VU0 (COP2)] Control register write ({s}) @ $FBRST = 0x{X:0>8}.", .{@typeName(T), data});

            if ((data & 1) != 0) {
                info("   [VU0 (COP2)] VU0 force break.", .{});
            }
            if ((data & (1 << 1)) != 0) {
                info("   [VU0 (COP2)] VU0 reset.", .{});
            }
            if ((data & (1 << 8)) != 0) {
                info("   [VU0 (COP2)] VU1 force break.", .{});
            }
            if ((data & (1 << 9)) != 0) {
                info("   [VU0 (COP2)] VU1 reset.", .{});
            }
        },
        else => {

        }
    }
}
