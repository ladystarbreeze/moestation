//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! core/bus.zig - System bus module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const Allocator = std.mem.Allocator;

const openFile = std.fs.cwd().openFile;
const OpenMode = std.fs.File.OpenMode;

const dmac  = @import("dmac.zig");
const gif   = @import("gif.zig");
const gs    = @import("gs.zig");
const intc  = @import("intc.zig");
const timer = @import("timer.zig");
const vu0   = @import("vu0.zig");

/// Memory base addresses
const MemBase = enum(u32) {
    Ram     = 0x0000_0000,
    Timer   = 0x1000_0000,
    Ipu     = 0x1000_2000,
    Gif     = 0x1000_3000,
    Vif0    = 0x1000_3800,
    Vif1    = 0x1000_3C00,
    Dmac    = 0x1000_8000,
    Vu0Code = 0x1100_0000,
    Vu0Data = 0x1100_4000,
    Vu1Code = 0x1100_8000,
    Vu1Data = 0x1100_C000,
    Gs      = 0x1200_0000,
    Bios    = 0x1FC0_0000,
};

/// Memory sizes
const MemSize = enum(u32) {
    Ram   = 0x200_0000,
    Timer = 0x000_1840,
    Ipu   = 0x000_0040,
    Gif   = 0x000_0100,
    Vu0   = 0x000_1000,
    Vu1   = 0x000_4000,
    Vif   = 0x000_0180,
    Dmac  = 0x000_7000,
    Gs    = 0x000_2000,
    Bios  = 0x040_0000,
};

// Memory arrays
var  bios: []u8 = undefined; // BIOS ROM
var rdram: []u8 = undefined; // RDRAM

// RDRAM registers
var  mchDrd: u32 = undefined;
var mchRicm: u32 = undefined;

var rdramSdevId: u32 = 0;

/// Initializes the bus module
pub fn init(allocator: Allocator, biosPath: []const u8) !void {
    info("   [Bus       ] Loading BIOS image {s}...", .{biosPath});

    // Load BIOS file
    const biosFile = try openFile(biosPath, .{.mode = OpenMode.read_only});
    defer biosFile.close();

    bios = try biosFile.reader().readAllAlloc(allocator, @enumToInt(MemSize.Bios));

    rdram = try allocator.alloc(u8, @enumToInt(MemSize.Ram));

    vu0.vuCode = try allocator.alloc(u8, @enumToInt(MemSize.Vu0));
    vu0.vuMem  = try allocator.alloc(u8, @enumToInt(MemSize.Vu0));

    info("   [Bus       ] Successfully loaded BIOS.", .{});
}

/// Deinitializes the bus module
pub fn deinit(allocator: Allocator) void {
    allocator.free(bios );
    allocator.free(rdram);
    allocator.free(vu0.vuCode);
    allocator.free(vu0.vuMem);
}

/// Reads data from the system bus
pub fn read(comptime T: type, addr: u32) T {
    assert(T == u8 or T == u16 or T == u32 or T == u64 or T == u128);

    var data: T = undefined;

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &rdram[addr]), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Ipu) and addr < (@enumToInt(MemBase.Ipu) + @enumToInt(MemSize.Ipu))) {
        if (T != u32) {
            @panic("Unhandled read @ IPU I/O");
        }
        
        warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (IPU).", .{@typeName(T), addr});

        data = 0;
    } else if (addr >= @enumToInt(MemBase.Gif) and addr < (@enumToInt(MemBase.Gif) + @enumToInt(MemSize.Gif))) {
        if (T != u32) {
            @panic("Unhandled read @ GIF I/O");
        }

        data = gif.read(addr);
    } else if (addr >= @enumToInt(MemBase.Dmac) and addr < (@enumToInt(MemBase.Dmac) + @enumToInt(MemSize.Dmac))) {
        if (T != u32) {
            @panic("Unhandled read @ DMAC I/O");
        }

        data = dmac.read(addr);
    } else if (addr >= 0x1A00_0000 and addr < 0x1FC0_0000) {
        warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (IOP).", .{@typeName(T), addr});

        data = 0;
    } else if (addr >= @enumToInt(MemBase.Bios) and addr < (@enumToInt(MemBase.Bios) + @enumToInt(MemSize.Bios))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &bios[addr - @enumToInt(MemBase.Bios)]), @sizeOf(T));
    } else {
        switch (addr) {
            0x1000_F000 => {
                if (T != u32) {
                    @panic("Unhandled read @ INTC_STAT");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (INTC_STAT).", .{@typeName(T), addr});

                data = intc.getStat();
            },
            0x1000_F010 => {
                if (T != u32) {
                    @panic("Unhandled read @ INTC_MASK");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (INTC_MASK).", .{@typeName(T), addr});

                data = intc.getMask();
            },
            0x1000_F430 => {
                if (T != u32) {
                    @panic("Unhandled read @ MCH_RICM");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (MCH_RICM).", .{@typeName(T), addr});

                data = 0;
            },
            0x1000_F440 => {
                if (T != u32) {
                    @panic("Unhandled read @ MCH_DRD");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (MCH_DRD).", .{@typeName(T), addr});

                const sop = @truncate(u4, mchRicm >> 6);

                if (sop == 0) {
                    const sa = @truncate(u8, mchRicm >> 16);

                    switch (sa) {
                        0x21 => {
                            info("   [RDRAM     ] Register 0x21 (Init).", .{});

                            if (rdramSdevId < 2) {
                                rdramSdevId += 1;

                                data = 0x1F;
                            } else {
                                data = 0;
                            }
                        },
                        0x40 => {
                            info("   [RDRAM     ] Register 0x40 (DevId).", .{});

                            data = mchRicm & 0x1F;
                        },
                        else => {
                            err("  [RDRAM     ] Unhandled RDRAM register 0x{X:0>2}.", .{sa});

                            assert(false);
                        }
                    }
                } else {
                    data = 0;
                }
            },
            0x1000_F130 => data = 0,
            0x1000_F400, 0x1000_F410 => {
                warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (Unknown).", .{@typeName(T), addr});

                data = 0;
            },
            else => {
                err("  [Bus       ] Unhandled read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

                assert(false);
            }
        }
    }

    return data;
}

/// Writes data to the system bus
pub fn write(comptime T: type, addr: u32, data: T) void {
    assert(T == u8 or T == u16 or T == u32 or T == u64 or T == u128);

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &rdram[addr]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Timer) and addr < (@enumToInt(MemBase.Timer) + @enumToInt(MemSize.Timer))) {
        if (T != u32) {
            @panic("Unhandled write @ Timer I/O");
        }

        timer.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Ipu) and addr < (@enumToInt(MemBase.Ipu) + @enumToInt(MemSize.Ipu))) {
        if (T != u32) {
            @panic("Unhandled write @ IPU I/O");
        }

        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (IPU) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Gif) and addr < (@enumToInt(MemBase.Gif) + @enumToInt(MemSize.Gif))) {
        if (T != u32) {
            @panic("Unhandled write @ GIF I/O");
        }

        gif.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Vif0) and addr < (@enumToInt(MemBase.Vif0) + @enumToInt(MemSize.Vif))) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VIF0) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Vif1) and addr < (@enumToInt(MemBase.Vif1) + @enumToInt(MemSize.Vif))) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VIF1) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Dmac) and addr < (@enumToInt(MemBase.Dmac) + @enumToInt(MemSize.Dmac))) {
        if (T != u32) {
            @panic("Unhandled write @ DMAC I/O");
        }

        dmac.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Vu0Code) and addr < (@enumToInt(MemBase.Vu0Code) + @enumToInt(MemSize.Vu0))) {
        info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (VU0 Code) = 0x{X}.", .{@typeName(T), addr, data});

        @memcpy(@ptrCast([*]u8, &vu0.vuCode[addr - @enumToInt(MemBase.Vu0Code)]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Vu0Data) and addr < (@enumToInt(MemBase.Vu0Data) + @enumToInt(MemSize.Vu0))) {
        info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (VU0 Data) = 0x{X}.", .{@typeName(T), addr, data});

        @memcpy(@ptrCast([*]u8, &vu0.vuMem[addr - @enumToInt(MemBase.Vu0Data)]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Vu1Code) and addr < (@enumToInt(MemBase.Vu1Code) + @enumToInt(MemSize.Vu1))) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VU1 Code) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Vu1Data) and addr < (@enumToInt(MemBase.Vu1Data) + @enumToInt(MemSize.Vu1))) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VU1 Data) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Gs) and addr < (@enumToInt(MemBase.Gs) + @enumToInt(MemSize.Gs))) {
        if (T != u64) {
            @panic("Unhandled write @ GS I/O");
        }

        gs.writePriv(addr, data);
    } else if (addr >= 0x1A00_0000 and addr < 0x1FC0_0000) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (IOP) = 0x{X}.", .{@typeName(T), addr, data});
    } else {
        switch (addr) {
            0x1000_4000 => {
                if (T != u128) {
                    @panic("Unhandled write @ VIF0 FIFO");
                }

                warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VIF0 FIFO) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1000_5000 => {
                if (T != u128) {
                    @panic("Unhandled write @ VIF1 FIFO");
                }

                warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VIF1 FIFO) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1000_6000 => {
                if (T != u128) {
                    @panic("Unhandled write @ GIF FIFO");
                }

                gif.writeFifo(data);
            },
            0x1000_7010 => {
                if (T != u128) {
                    @panic("Unhandled write @ IPU In FIFO");
                }

                warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (IPU In FIFO) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1000_F000 => {
                if (T != u32) {
                    @panic("Unhandled write @ INTC_STAT");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (INTC_STAT) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setStat(data);
            },
            0x1000_F010 => {
                if (T != u32) {
                    @panic("Unhandled write @ INTC_MASK");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (INTC_MASK) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setMask(data);
            },
            0x1000_F180 => {
                if (T != u8) {
                    @panic("Unhandled write @ KPUTCHAR");
                }

                // info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (KPUTCHAR) = 0x{X}.", .{@typeName(T), addr, data});

                if (data != 0) {
                    const stdOut = std.io.getStdOut().writer();

                    stdOut.print("{c}", .{data}) catch unreachable;
                }
            },
            0x1000_F430 => {
                if (T != u32) {
                    @panic("Unhandled write @ MCH_RICM");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (MCH_RICM) = 0x{X}.", .{@typeName(T), addr, data});

                assert(T == u32);

                const  sa = @truncate(u8, data >> 16);
                const sbc = @truncate(u4, data >>  6);

                if ((sa == 0x21) and (sbc == 1) and ((mchDrd & (1 << 7)) == 0)) {
                    rdramSdevId = 0;
                }

                mchRicm = data & ~@as(u32, 0x80000000);
            },
            0x1000_F440 => {
                if (T != u32) {
                    @panic("Unhandled write @ MCH_DRD");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (MCH_DRD) = 0x{X}.", .{@typeName(T), addr, data});

                mchDrd = data;
            },
            0x1000_F100, 0x1000_F120, 0x1000_F140, 0x1000_F150,
            0x1000_F400, 0x1000_F410, 0x1000_F420, 0x1000_F450, 0x1000_F460, 0x1000_F480, 0x1000_F490,
            0x1000_F500, 0x1000_F510 => warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (Unknown) = 0x{X}.", .{@typeName(T), addr, data}),
            else => {
                err("  [Bus       ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X}.", .{@typeName(T), addr, data});

                assert(false);
            }
        }
    }
}
