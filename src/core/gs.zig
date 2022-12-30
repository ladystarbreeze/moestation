//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! gs.zig - Graphics Synthesizer
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const intc = @import("intc.zig");

const IntSource = intc.IntSource;
const IntSourceIop = intc.IntSourceIop;

const timer = @import("timer.zig");
const timerIop = @import("timer_iop.zig");

/// GS registers
pub const GsReg = enum(u8) {
    Prim       = 0x00,
    Rgbaq      = 0x01,
    St         = 0x02,
    Uv         = 0x03,
    Xyzf2      = 0x04,
    Xyz2       = 0x05,
    Tex01      = 0x06,
    Tex02      = 0x07,
    Clamp1     = 0x08,
    Clamp2     = 0x09,
    Fog        = 0x0A,
    Xyzf3      = 0x0C,
    Xyz3       = 0x0D,
    AddrData   = 0x0E,
    Tex11      = 0x14,
    Tex12      = 0x15,
    Tex21      = 0x16,
    Tex22      = 0x17,
    XyOffset1  = 0x18,
    XyOffset2  = 0x19,
    PrModeCont = 0x1A,
    PrMode     = 0x1B,
    TexClut    = 0x1C,
    ScanMsk    = 0x22,
    MipTbp11   = 0x34,
    MipTbp12   = 0x35,
    MipTbp21   = 0x36,
    MipTbp22   = 0x37,
    TexA       = 0x3B,
    FogCol     = 0x3D,
    TexFlush   = 0x3F,
    Scissor1   = 0x40,
    Scissor2   = 0x41,
    Alpha1     = 0x42,
    Alpha2     = 0x43,
    Dimx       = 0x44,
    Dthe       = 0x45,
    ColClamp   = 0x46,
    Test1      = 0x47,
    Test2      = 0x48,
    Pabe       = 0x49,
    Fba1       = 0x4A,
    Fba2       = 0x4B,
    Frame1     = 0x4C,
    Frame2     = 0x4D,
    Zbuf1      = 0x4E,
    Zbuf2      = 0x4F,
    BitBltBuf  = 0x50,
    TrxPos     = 0x51,
    TrxReg     = 0x52,
    TrxDir     = 0x53,
    Hwreg      = 0x54,
    Signal     = 0x60,
    Finish     = 0x61,
    Label      = 0x62,
};

/// GS privileged registers
const PrivReg = enum(u32) {
    Pmode    = 0x1200_0000,
    Smode1   = 0x1200_0010,
    Smode2   = 0x1200_0020,
    Srfsh    = 0x1200_0030,
    Synch1   = 0x1200_0040,
    Synch2   = 0x1200_0050,
    Syncv    = 0x1200_0060,
    Dispfb1  = 0x1200_0070,
    Display1 = 0x1200_0080,
    Dispfb2  = 0x1200_0090,
    Display2 = 0x1200_00A0,
    Extbuf   = 0x1200_00B0,
    Extdata  = 0x1200_00C0,
    Extwrite = 0x1200_00D0,
    Bgcolor  = 0x1200_00E0,
    GsCsr    = 0x1200_1000,
    GsImr    = 0x1200_1010,
    Busdir   = 0x1200_1040,
    Siglblid = 0x1200_1080,
};

const  cyclesLine: i64 = 9371;
const cyclesFrame: i64 = cyclesLine * 60;

/// Simple Line counter
var cyclesToNextLine: i64 = 0;
var lines: i64 = 0;

// GS registers
var gsRegs: [0x63]u64 = undefined;

var vtxCount: i32 = 0;

/// Writes data to a GS register
pub fn write(addr: u8, data: u64) void {
    if (addr > @enumToInt(GsReg.Label)) {
        err("  [GS        ] Invalid GS register address 0x{X:0>2}.", .{addr});

        assert(false);
    }

    info("   [GS        ] Write @ 0x{X:0>2} ({s}) = 0x{X:0>16}.", .{addr, @tagName(@intToEnum(GsReg, addr)), data});

    gsRegs[addr] = data;
}

/// Writes data to a GS register (from GIF)
pub fn writePacked(addr: u4, data: u128) void {
    switch (addr) {
        @enumToInt(GsReg.Prim) => {
            write(@enumToInt(GsReg.Prim), @truncate(u11, data));
        },
        @enumToInt(GsReg.Rgbaq) => {
            var rgbaq: u64 = 0;

            // TODO: add Q!
            rgbaq |= @as(u64, @truncate(u8, data));
            rgbaq |= @as(u64, @truncate(u8, data >> 32)) <<  8;
            rgbaq |= @as(u64, @truncate(u8, data >> 64)) << 16;
            rgbaq |= @as(u64, @truncate(u8, data >> 96)) << 24;

            write(@enumToInt(GsReg.Rgbaq), rgbaq);
        },
        @enumToInt(GsReg.Xyzf2) => {
            var xyzf: u64 = 0;

            xyzf |= @as(u64, @truncate(u16, data));
            xyzf |= @as(u64, @truncate(u16, data >>  32)) << 16;
            xyzf |= @as(u64, @truncate(u24, data >>  68)) << 32;
            xyzf |= @as(u64, @truncate(u8 , data >> 100)) << 56;

            if ((data & (1 << 111)) != 0) {
                write(@enumToInt(GsReg.Xyzf3), xyzf);
            } else {
                write(@enumToInt(GsReg.Xyzf2), xyzf);
            }
        },
        @enumToInt(GsReg.AddrData) => {
            const reg = @truncate(u8, data >> 64);

            write(reg, @truncate(u64, data));
        },
        else => {
            err("  [GS        ] Unhandled PACKED write @ 0x{X} = 0x{X:0>32}.", .{addr, data});

            assert(false);
        }
    }
}

/// Writes data to HWREG
pub fn writeHwreg(data: u64) void {
    info("   [GS        ] Write @ HWREG = 0x{X:0>16}.", .{data});
}

/// Writes data to privileged register
pub fn writePriv(addr: u32, data: u64) void {
    switch (addr) {
        @enumToInt(PrivReg.Smode1) => {
            info("   [GS        ] Write @ 0x{X:0>8} (SMODE1) = 0x{X:0>16}.", .{addr, data});
        },
        @enumToInt(PrivReg.Smode2) => {
            info("   [GS        ] Write @ 0x{X:0>8} (SMODE2) = 0x{X:0>16}.", .{addr, data});
        },
        @enumToInt(PrivReg.Srfsh) => {
            info("   [GS        ] Write @ 0x{X:0>8} (SRFSH) = 0x{X:0>16}.", .{addr, data});
        },
        @enumToInt(PrivReg.Synch1) => {
            info("   [GS        ] Write @ 0x{X:0>8} (SYNCH1) = 0x{X:0>16}.", .{addr, data});
        },
        @enumToInt(PrivReg.Synch2) => {
            info("   [GS        ] Write @ 0x{X:0>8} (SYNCH2) = 0x{X:0>16}.", .{addr, data});
        },
        @enumToInt(PrivReg.Syncv) => {
            info("   [GS        ] Write @ 0x{X:0>8} (SYNCV) = 0x{X:0>16}.", .{addr, data});
        },
        @enumToInt(PrivReg.GsCsr) => {
            info("   [GS        ] Write @ 0x{X:0>8} (GS_CSR) = 0x{X:0>16}.", .{addr, data});

            if ((data & (1 << 9)) != 0) {
                info("   [GS        ] GS reset.", .{});
            }
        },
        else => {
            warn("[GS        ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});
        }
    }
}

/// Steps the GS module
pub fn step(cyclesElapsed: i64) void {
    cyclesToNextLine += cyclesElapsed;

    if (cyclesToNextLine >= cyclesLine) {
        cyclesToNextLine = 0;

        lines += 1;

        timer.stepHblank();
        timerIop.stepHblank();

        if (lines == 480) {
            intc.sendInterrupt(IntSource.VblankStart);
            intc.sendInterruptIop(IntSourceIop.VblankStart);
        } else if (lines == 544) {
            lines = 0;

            intc.sendInterrupt(IntSource.VblankEnd);
            intc.sendInterruptIop(IntSourceIop.VblankEnd);
        }
    }
}
