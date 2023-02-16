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

const cpu  = @import("cpu.zig");
const dmac = @import("dmac.zig");

const Channel = dmac.Channel;

const gs = @import("gs.zig");

const GsReg = gs.GsReg;

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
pub const ActivePath = enum(u2) {
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

/// PATH1 address
var p1Addr: u16 = 0;

/// Current NREGS and NLOOP
var nloop: u15 = 0;
var nregs: u6  = 0;

var setFinish = false;

/// Reads data from GIF I/O
pub fn read(addr: u32) u32 {
    var data: u32 = 0;

    switch (addr) {
        @enumToInt(GifReg.GifStat) => {
            //info("   [GIF       ] Read @ 0x{X:0>8} (GIF_STAT).", .{addr});

            data = gifStat.get() | (@truncate(u32, gifFifo.readableLength()) << 24);

            //info("GIF_STAT = 0x{X:0>8}", .{data});
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

                dmac.setRequest(Channel.Path3, true);

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

    // Attempt to make PATH3 the new active path
    setActivePath(ActivePath.Path3);

    gifFifo.writeItem(data) catch {
        err("  [GIF       ] GIF FIFO is full.", .{});
        
        assert(false);
    };

    if (gifFifo.readableLength() == 16) {
        dmac.setRequest(Channel.Path3, false);
    }
}

/// Sets FINISH signal after DMA finishes
pub fn scheduleFinish() void {
    setFinish = true;
}

/// Returns active PATH
pub fn getActivePath() ActivePath {
    return @intToEnum(ActivePath, gifStat.apath);
}

/// Returns true if PATH1 is active
pub fn isP1Active() bool {
    return @intToEnum(ActivePath, gifStat.apath) == ActivePath.Path1;
}

/// Returns true if PATH2 is active
pub fn isP2Active() bool {
    return @intToEnum(ActivePath, gifStat.apath) == ActivePath.Path2;
}

/// Returns true if PATH3 is pending
pub fn isP3Pending() bool {
    return gifStat.p3q;
}

/// Returns queued PATH
pub fn getNextPath() ActivePath {
    if (gifStat.p1q) {
        gifStat.p1q = false;

        return ActivePath.Path1;
    }

    if (gifStat.p2q) {
        gifStat.p2q = false;

        return ActivePath.Path2;
    }

    if (gifStat.p3q) {
        gifStat.p3q = false;

        return ActivePath.Path1;
    }

    return ActivePath.Idle;
}

/// Sets new active GIF PATH (queues PATH if GIF is active)
pub fn setActivePath(path: ActivePath) void {
    switch (@intToEnum(ActivePath, gifStat.apath)) {
        ActivePath.Idle  => {},
        ActivePath.Path1 => {
            switch (path) {
                ActivePath.Path2 => {
                    gifStat.p2q = true;
                },
                ActivePath.Path3 => {
                    gifStat.p3q = true;
                },
                else => {}
            }

            return;
        },
        ActivePath.Path2 => {
            switch (path) {
                ActivePath.Path1 => {
                    gifStat.p1q = true;
                },
                ActivePath.Path3 => {
                    gifStat.p3q = true;
                },
                else => {}
            }

            return;
        },
        ActivePath.Path3 => {
            switch (path) {
                ActivePath.Path1 => {
                    gifStat.p1q = true;
                },
                ActivePath.Path2 => {
                    gifStat.p2q = true;
                },
                else => {}
            }

            return;
        }
    }

    if (path == ActivePath.Idle) return;

    std.debug.print("[GIF       ] PATH{} active\n", .{@enumToInt(path)});

    gifStat.apath = @enumToInt(path);
    gifStat.oph   = true;
}

/// Sets VU mem address for PATH1
pub fn setPath1Addr(addr: u16) void {
    p1Addr = addr;
}

/// Starts GIF PATH1 (VU1/XGKICK), returns false if GIF is busy
pub fn startPath1() bool {
    setActivePath(ActivePath.Path1);

    if (@intToEnum(ActivePath, gifStat.apath) != ActivePath.Path1) return false;

    return true;
}

/// Reads data from PATH1
pub fn readPath1() u128 {
    const data = cpu.vu[1].readData(u128, p1Addr << 4);

    p1Addr += 1;

    return data;
}

/// Writes data to GIF FIFO via PATH2
pub fn writePath2(data: u128) void {
    std.debug.print("[GIF       ] PATH2 write = 0x{X:0>32}\n", .{data});

    if (!gifTag.hasTag) {
        decodeGifTag(data);

        if (gifTag.nloop == 0) {
            if (gifTag.eop) {
                std.debug.print("   [GIF       ] End of packet\n", .{});

                pathEnd();
            }

            gifTag.hasTag = false;
        } else {
            if (gifTag.prim) {
                gs.write(@enumToInt(GsReg.Prim), gifTag.pdata);
            }

            nloop = gifTag.nloop;
        }
    } else {
        switch (gifTag.fmt) {
            Format.Packed  => doPacked(data),
            Format.Reglist => {
                doReglist(@truncate(u64, data));
                doReglist(@truncate(u64, data >> 64));
            },
            Format.Image   => doImage(data),
        }
    }
}

/// Writes data to GIF FIFO via PATH3
pub fn writePath3(data: u128) void {
    writeFifo(data);
}

/// Returns GIF to idle state or selects new PATH
pub fn pathEnd() void {
    gifStat.apath = @enumToInt(ActivePath.Idle);

    gifStat.oph = false;

    if (setFinish) {
        gs.setFinish();

        setFinish = false;
    }

    setActivePath(getNextPath());
}

/// Decodes a GIFtag
fn decodeGifTag(tag: u128) void {
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

    // Initialize GS Q register
    gs.initQ();
}

/// Steps the GIF
pub fn step() void {
    var data: u128 = undefined;

    switch (@intToEnum(ActivePath, gifStat.apath)) {
        ActivePath.Idle, ActivePath.Path2 => return,
        ActivePath.Path1 => data = readPath1(),
        ActivePath.Path3 => {
            if (gifFifo.readableLength() == 0) return;

            data = readFifo();
        },
    }

    if (!gifTag.hasTag) {
        decodeGifTag(data);

        if (gifTag.nloop == 0) {
            if (gifTag.eop) {
                info("   [GIF       ] End of packet.", .{});

                pathEnd();
            }

            gifTag.hasTag = false;
        } else {
            if (gifTag.prim) {
                gs.write(@enumToInt(GsReg.Prim), gifTag.pdata);
            }

            nloop = gifTag.nloop;
        }
    } else {
        switch (gifTag.fmt) {
            Format.Packed  => doPacked(data),
            Format.Reglist => {
                doReglist(@truncate(u64, data));
                doReglist(@truncate(u64, data >> 64));
            },
            Format.Image   => doImage(data),
        }
    }
}

/// Processes an IMAGE primitive
fn doImage(data: u128) void {
    if (nloop == gifTag.nloop) {
        info("   [GIF       ] IMAGE mode. NLOOP = {}", .{gifTag.nloop});
    }

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
fn doPacked(data: u128) void {
    if (nregs == 0 and nloop == gifTag.nloop) {
        info("   [GIF       ] PACKED mode. NREGS = {}, NLOOP = {}", .{gifTag.nregs, gifTag.nloop});
    }

    const reg  = @truncate(u4, gifTag.regs >> (4 * nregs));

    gs.writePacked(reg, data);

    nregs += 1;

    if ((gifTag.nregs != 0 and nregs == gifTag.nregs) or (gifTag.nregs == 0 and nregs == 16)) {
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

/// Processes a REGLIST primitive
fn doReglist(data: u64) void {
    if (nregs == 0 and nloop == gifTag.nloop) {
        info("   [GIF       ] REGLIST mode. NREGS = {}, NLOOP = {}", .{gifTag.nregs, gifTag.nloop});
    }

    var reg = @truncate(u4, gifTag.regs >> (4 * nregs));

    gs.write(reg, data);

    nregs += 1;

    if ((gifTag.nregs != 0 and nregs == gifTag.nregs) or (gifTag.nregs == 0 and nregs == 16)) {
        nregs = 0;

        nloop -= 1;

        if (nloop == 0) {
            gifTag.hasTag = false;

            info("   [GIF       ] REGLIST mode end.", .{});

            if (gifTag.eop) {
                pathEnd();
            }
        }
    }
}
