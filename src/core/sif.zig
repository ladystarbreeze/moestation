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

const LinearFifo = std.fifo.LinearFifo;
const LinearFifoBufferType = std.fifo.LinearFifoBufferType;

/// SIF registers (EE)
const SifReg = enum(u32) {
    SifMscom = 0x1000_F200,
    SifSmcom = 0x1000_F210,
    SifMsflg = 0x1000_F220,
    SifSmflg = 0x1000_F230,
    SifCtrl  = 0x1000_F240,
    SifBd6   = 0x1000_F260,
};

/// SIF registers (IOP)
const SifRegIop = enum(u32) {
    SifSmcom = 0x1D00_0010,
    SifMsflg = 0x1D00_0020,
    SifSmflg = 0x1D00_0030,
    SifCtrl  = 0x1D00_0040,
    SifBd6   = 0x1D00_0060,
};

/// SIF registers
var mscom: u32 = 0;
var smcom: u32 = 0;
var msflg: u32 = 0;
var smflg: u32 = 0;
var   bd6: u32 = 0;

const SifFifo = LinearFifo(u32, LinearFifoBufferType{.Static = 32});

/// SBUS FIFOs
var sif0Fifo = SifFifo.init();
var sif1Fifo = SifFifo.init();

/// Reads data from SIF registers (from EE)
pub fn read(addr: u32) u32 {
    var data: u32 = undefined;

    switch (addr) {
        @enumToInt(SifReg.SifMscom) => {
            info("   [SIF       ] Read @ 0x{X:0>8} (SIF_MSCOM).", .{addr});

            data = mscom;
        },
        @enumToInt(SifReg.SifSmcom) => {
            info("   [SIF       ] Read @ 0x{X:0>8} (SIF_SMCOM).", .{addr});

            data = smcom;
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
        @enumToInt(SifRegIop.SifSmcom) => {
            info("   [SIF (IOP) ] Read @ 0x{X:0>8} (SIF_SMCOM).", .{addr});

            data = smcom;
        },
        @enumToInt(SifRegIop.SifMsflg) => {
            info("   [SIF (IOP) ] Read @ 0x{X:0>8} (SIF_MSFLG).", .{addr});

            data = msflg;
        },
        @enumToInt(SifRegIop.SifSmflg) => {
            info("   [SIF (IOP) ] Read @ 0x{X:0>8} (SIF_SMFLG).", .{addr});

            data = smflg;
        },
        @enumToInt(SifRegIop.SifCtrl) => {
            info("   [SIF (IOP) ] Read @ 0x{X:0>8} (SIF_CTRL).", .{addr});

            data = 0xF000_0002;
        },
        @enumToInt(SifRegIop.SifBd6) => {
            info("   [SIF (IOP) ] Read @ 0x{X:0>8} (SIF_BD6).", .{addr});

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

            msflg |= data;
        },
        @enumToInt(SifReg.SifSmflg) => {
            info("   [SIF       ] Write @ 0x{X:0>8} (SIF_SMFLG) = 0x{X:0>8}.", .{addr, data});

            msflg &= ~data;
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

/// Writes data to SIF registers (from IOP)
pub fn writeIop(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(SifRegIop.SifSmcom) => {
            info("   [SIF (IOP) ] Write @ 0x{X:0>8} (SIF_SMCOM) = 0x{X:0>8}.", .{addr, data});

            smcom = data;
        },
        @enumToInt(SifRegIop.SifSmflg) => {
            info("   [SIF (IOP) ] Write @ 0x{X:0>8} (SIF_SMFLG) = 0x{X:0>8}.", .{addr, data});

            smflg |= data;
        },
        @enumToInt(SifRegIop.SifCtrl) => {
            info("   [SIF (IOP) ] Write @ 0x{X:0>8} (SIF_CTRL) = 0x{X:0>8}.", .{addr, data});
        },
        else => {
            err("  [SIF (IOP) ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }
}

/// Writes data to SIF1 FIFO
pub fn writeSif1(data: u128) void {
    info("   [SIF (DMAC)] Write @ SIF1 FIFO = 0x{X:0>32}.", .{data});

    var i: u7 = 0;
    while (i < 4) : (i += 1) {
        sif1Fifo.writeItem(@truncate(u32, data >> (32 * i))) catch {
            err("  [SIF (DMAC)] Unable to write to SIF1 FIFO.", .{});
            
            assert(false);
        };
    }

    if (sif1Fifo.writableLength() < 16) {
        info("   [SIF (DMAC)] Clear EE request.", .{});
    }
}
