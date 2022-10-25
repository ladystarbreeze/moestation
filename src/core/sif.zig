//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! sif.zig - Subsystem Interface module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

/// SIF registers (EE)
const SifRegEe = enum(u32) {
    SifMscom = 0x1000_F200,
    SifMsflg = 0x1000_F220,
    SifSmflg = 0x1000_F230,
    SifCtrl  = 0x1000_F240,
    SifBd6   = 0x1000_F260,
};

/// SIF registers
var mscom: u32 = undefined;
var msflg: u32 = undefined;

/// Writes data to SIF registers (from EE)
pub fn writeEe(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(SifRegEe.SifMscom) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_MSCOM) = 0x{X:0>8}.", .{addr, data});

            mscom = data;
        },
        @enumToInt(SifRegEe.SifMsflg) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_MSFLG) = 0x{X:0>8}.", .{addr, data});

            msflg = data;
        },
        @enumToInt(SifRegEe.SifCtrl) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_CTRL) = 0x{X:0>8}.", .{addr, data});
        },
        @enumToInt(SifRegEe.SifBd6) => {
            warn("[SIF       ] Write @ 0x{X:0>8} (SIF_BD6) = 0x{X:0>8}.", .{addr, data});
        },
        else => {
            err("  [SIF       ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }
}
