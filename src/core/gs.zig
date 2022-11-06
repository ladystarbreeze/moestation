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

const cyclesFrame: i64 = 147_000_000 / 60;
const  cyclesLine: i64 = cyclesFrame / 544;
const  cyclesInit: i64 = cyclesLine * 480;

/// Simple VBLANK cycle counter
var cyclesToVblank = cyclesInit;

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
    cyclesToVblank -= cyclesElapsed;

    if (cyclesToVblank <= 0) {
        cyclesToVblank = cyclesFrame;

        intc.sendInterrupt(IntSource.VblankStart);
        intc.sendInterruptIop(IntSourceIop.VblankStart);
    }
}
