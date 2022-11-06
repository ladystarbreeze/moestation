//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! gif.zig - Graphics Interface
//!

const std = @import("std");

const assert = std.debug.assert;

const LinearFifo = std.fifo.LinearFifo;
const LinearFifoBufferType = std.fifo.LinearFifoBufferType;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const dmac = @import("dmac.zig");

const Channel = dmac.Channel;

const gs = @import("gs.zig");

/// GIF I/O
const GifReg = enum(u32) {
    GifCtrl  = 0x1000_3000,
    GifMode  = 0x1000_3010,
    GifStat  = 0x1000_3020,
    GifTag0  = 0x1000_3040,
    GifTag1  = 0x1000_3050,
    GifTag2  = 0x1000_3060,
    GifTag3  = 0x1000_3070,
    GifCnt   = 0x1000_3080,
    GifP3Cnt = 0x1000_3090,
    GifP3Tag = 0x1000_30A0,
};

/// GIF_STAT
const GifStat = struct {
      m3r: bool = false, // PATH3 Masked
      m3p: bool = false, // PATH3 Masked (MASKP3)
      imt: bool = false, // InterMittent transfer
      pse: bool = false, // PauSE
      ip3: bool = false, // Interrupted PATH3
      p3q: bool = false, // PATH3 Queued
      p2q: bool = false, // PATH2 Queued
      p1q: bool = false, // PATH1 Queued
      oph: bool = false, // Output PatH
    apath: u2   = 0,     // Active PATH
      dir: bool = false, // DIRection
    
    /// Returns GIF_STAT
    pub fn get(self: GifStat) u32 {
        var data: u32 = 0;

        data |= @as(u32, @bitCast(u1, self.m3r));
        data |= @as(u32, @bitCast(u1, self.m3p)) << 1;
        data |= @as(u32, @bitCast(u1, self.imt)) << 2;
        data |= @as(u32, @bitCast(u1, self.pse)) << 3;
        data |= @as(u32, @bitCast(u1, self.ip3)) << 5;
        data |= @as(u32, @bitCast(u1, self.p3q)) << 6;
        data |= @as(u32, @bitCast(u1, self.p2q)) << 7;
        data |= @as(u32, @bitCast(u1, self.p1q)) << 8;
        data |= @as(u32, @bitCast(u1, self.oph)) << 9;
        data |= @as(u32, self.apath) << 10;
        data |= @as(u32, @bitCast(u1, self.dir)) << 12;

        return data;
    }
};

/// Active PATH
const ActivePath = enum(u2) {
    Idle,
    Path1,
    Path2,
    Path3,
};

/// GIFtag data format
const Format = enum(u2) {
    Packed,
    Reglist,
    Image,
};

/// GIFtag
const GifTag = struct {
    tag: u128 = undefined,
    
    // GIFtag fields
    nloop: u15    = 0,
      eop: bool   = false,
     prim: bool   = false,
    pdata: u11    = 0,
      fmt: Format = undefined,
    nregs: u4     = 0,
     regs: u64    = 0,

    hasTag: bool = false,
};

const GifFifo = LinearFifo(u128, LinearFifoBufferType{.Static = 16});

/// GIF FIFO
var gifFifo = GifFifo.init();

/// GIF_STAT
var gifStat = GifStat{};

/// Current GIF tag
var gifTag = GifTag{};

/// Current NREGS and NLOOP
var nloop: u15 = 0;
var nregs: u5  = 0;

/// Reads data from GIF I/O
pub fn read(addr: u32) u32 {
    var data: u32 = 0;

    switch (addr) {
        @enumToInt(GifReg.GifStat) => {
            info("   [GIF       ] Read @ 0x{X:0>8} (GIF_STAT).", .{addr});

            data = gifStat.get() | (@truncate(u32, gifFifo.readableLength()) << 24);
        },
        else => {
            err("  [GIF       ] Unhandled read @ 0x{X:0>8}.", .{addr});

            assert(false);
        }
    }

    return data;
}

/// Reads data from the GIF FIFO
pub fn readFifo() u128 {
    const data = gifFifo.readItem().?;

    if (gifFifo.readableLength() != 16) {
        dmac.setRequest(Channel.Path3, true);
    }

    return data;
}

/// Writes data to GIF I/O
pub fn write(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(GifReg.GifCtrl) => {
            info("   [GIF       ] Write @ 0x{X:0>8} (GIF_CTRL) = 0x{X:0>8}.", .{addr, data});

            if ((data & 1) != 0) {
                info("   [GIF       ] GIF reset.", .{});

                pathEnd();

                gifFifo = GifFifo.init();

                gifTag.hasTag = false;

                nregs = 0;
                nloop = 0;
            }
        },
        else => {
            err("  [GIF       ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }
}

/// Writes data to GIF FIFO
pub fn writeFifo(data: u128) void {
    //info("   [GIF       ] Write @ FIFO = 0x{X:0>32}.", .{data});

    gifFifo.writeItem(data) catch {
        err("  [GIF       ] GIF FIFO is full.", .{});
        
        assert(false);
    };

    if (gifFifo.readableLength() == 16) {
        dmac.setRequest(Channel.Path3, false);
    }

    if (gifStat.apath == @enumToInt(ActivePath.Idle)) {
        info("   [GIF       ] PATH3 active.", .{});

        gifStat.apath = @enumToInt(ActivePath.Path3);

        gifStat.oph = true;
    }
}

/// Writes data to GIF FIFO via PATH3
pub fn writePath3(data: u128) void {
    writeFifo(data);
}

/// Decodes a GIFtag
fn decodeGifTag() void {
    const tag = readFifo();

    info("   [GIF       ] New GIFtag = 0x{X:0>32}.", .{tag});

    gifTag.tag = tag;

    gifTag.nloop = @truncate(u15, tag);
    gifTag.eop   = (tag & (1 << 15)) != 0;
    gifTag.prim  = (tag & (1 << 46)) != 0;
    gifTag.pdata = @truncate(u11, tag >> 47);
    gifTag.nregs = @truncate(u4 , tag >> 60);
    gifTag.regs  = @truncate(u64, tag >> 64);
    
    switch (@truncate(u2, tag >> 58)) {
        0    => gifTag.fmt = Format.Packed,
        1    => gifTag.fmt = Format.Reglist,
        2, 3 => gifTag.fmt = Format.Image,
    }

    gifTag.hasTag = true;
}

/// Returns GIF to idle state
pub fn pathEnd() void {
    gifStat.apath = @enumToInt(ActivePath.Idle);

    gifStat.oph = false;
}

/// Steps the GIF
pub fn step() void {
    if (gifFifo.readableLength() == 0) {
        return;
    }

    if (!gifTag.hasTag) {
        decodeGifTag();

        if (gifTag.nloop == 0) {
            if (gifTag.eop) {
                info("   [GIF       ] End of packet.", .{});
            }

            gifTag.hasTag = false;
        } else {
            if (gifTag.prim) {
                err("  [GIF       ] Unhandled PRIM write.", .{});

                assert(false);
            }

            nloop = gifTag.nloop;
        }
    } else {
        switch (gifTag.fmt) {
            Format.Packed => doPacked(),
            Format.Image  => doImage(),
            else => {
                err("  [GIF       ] Unhandled {s} format.", .{@tagName(gifTag.fmt)});

                assert(false);
            }
        }
    }
}

/// Processes an IMAGE primitive
fn doImage() void {
    if (nloop == gifTag.nloop) {
        info("   [GIF       ] IMAGE mode. NLOOP = {}", .{gifTag.nloop});
    }

    const data = readFifo();

    gs.writeHwreg(@truncate(u64, data));
    gs.writeHwreg(@truncate(u64, data >> 64));

    nloop -= 1;

    if (nloop == 0) {
        gifTag.hasTag = false;

        info("   [GIF       ] IMAGE mode end.", .{});

        if (gifTag.eop) {
            pathEnd();
        }
    }
}

/// Processes a PACKED primitive
fn doPacked() void {
    if (nregs == 0 and nloop == gifTag.nloop) {
        info("   [GIF       ] PACKED mode. NREGS = {}, NLOOP = {}", .{gifTag.nregs, gifTag.nloop});
    }

    const data = readFifo();
    const reg  = @truncate(u4, gifTag.regs >> (4 * nregs));

    gs.writePacked(reg, data);

    nregs += 1;

    if (nregs == gifTag.nregs or nregs == 16) {
        nregs = 0;

        nloop -= 1;

        if (nloop == 0) {
            gifTag.hasTag = false;

            info("   [GIF       ] PACKED mode end.", .{});

            if (gifTag.eop) {
                pathEnd();
            }
        }
    }
}
