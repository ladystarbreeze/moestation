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
const SifReg = enum(u32) {
    SifMscom = 0x1000_F200,
    SifMsflg = 0x1000_F220,
    SifSmflg = 0x1000_F230,
    SifCtrl  = 0x1000_F240,
    SifBd6   = 0x1000_F260,
};

/// SIF registers (IOP)
const SifRegIop = enum(u32) {
    SifBd6 = 0x1D00_0060,
};

/// SIF registers
var mscom: u32 = undefined;
var msflg: u32 = undefined;
var smflg: u32 = undefined;
var   bd6: u32 = undefined;

/// Reads data from SIF registers (from EE)
pub fn read(addr: u32) u32 {
    var data: u32 = undefined;

    switch (addr) {
        @enumToInt(SifReg.SifMscom) => {
            info("   [SIF       ] Read @ 0x{X:0>8} (SIF_MSCOM).", .{addr});

            data = mscom;
        },
        @enumToInt(SifReg.SifMsflg) => {
            info("   [SIF       ] Read @ 0x{X:0>8} (SIF_MSFLG).", .{addr});

            data = msflg;
        },
        @enumToInt(SifReg.SifSmflg) => {
            //info("   [SIF       ] Read @ 0x{X:0>8} (SIF_SMFLG).", .{addr});

            data = smflg;
        },
        else => {
            err("  [SIF       ] Unhandled read @ 0x{X:0>8}.", .{addr});

            assert(false);
        }
    }

    return data;
}

/// Reads data from SIF registers (from IOP)
pub fn readIop(addr: u32) u32 {
    var data: u32 = undefined;

    switch (addr) {
        @enumToInt(SifRegIop.SifBd6) => {
            info("   [SIF       ] Read @ 0x{X:0>8} (SIF_BD6).", .{addr});

            data = bd6;
        },
        else => {
            err("  [SIF (IOP) ] Unhandled read @ 0x{X:0>8}.", .{addr});

            assert(false);
        }
    }
    
    return data;
}

/// Writes data to SIF registers (from EE)
pub fn write(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(SifReg.SifMscom) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_MSCOM) = 0x{X:0>8}.", .{addr, data});

            mscom = data;
        },
        @enumToInt(SifReg.SifMsflg) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_MSFLG) = 0x{X:0>8}.", .{addr, data});

            msflg = data;
        },
        @enumToInt(SifReg.SifCtrl) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_CTRL) = 0x{X:0>8}.", .{addr, data});
        },
        @enumToInt(SifReg.SifBd6) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_BD6) = 0x{X:0>8}.", .{addr, data});

            bd6 = data;
        },
        else => {
            err("  [SIF       ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }
}
