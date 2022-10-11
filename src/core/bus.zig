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

const intc = @import("intc.zig");

/// KPUTCHAR register
const Kputchar = struct {
    msg: [256]u8 = undefined,

    idx: u9 = 0,

    /// Writes a character to KPUTCHAR
    pub fn write(self: *Kputchar, c: u8) void {
        if (self.idx >= 256) {
            err("  [KPUTCHAR  ] Message buffer overflowed.", .{});

            assert(false);
        }

        if (c == 0x0A) {
            self.flush();
        } else {
            self.msg[self.idx] = c;

            self.idx += 1;
        }
    }

    /// Prints out and resets message
    fn flush(self: *Kputchar) void {
        info("   [KPUTCHAR  ] {s}", .{self.msg});

        var i: usize = 0;
        while (i < 256) : (i += 1) {
            self.msg[i] = 0;
        }

        self.idx = 0;
    }
};

/// Memory base addresses
const MemBase = enum(u32) {
    Ram  = 0x0000_0000,
    Bios = 0x1FC0_0000,
};

/// Memory sizes
const MemSize = enum(u32) {
    Ram  = 0x200_0000,
    Bios = 0x040_0000,
};

// Memory arrays
var  bios: []u8 = undefined; // BIOS ROM
var rdram: []u8 = undefined; // RDRAM

/// KPUTCHAR
var kputchar: Kputchar = Kputchar{};

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

    // Clear KPUTCHAR
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        kputchar.msg[i] = 0;
    }

    info("   [Bus       ] Successfully loaded BIOS.", .{});
}

/// Deinitializes the bus module
pub fn deinit(allocator: Allocator) void {
    allocator.free(bios );
    allocator.free(rdram);
}

/// Reads data from the system bus
pub fn read(comptime T: type, addr: u32) T {
    assert(T == u8 or T == u16 or T == u32 or T == u64 or T == u128);

    var data: T = undefined;

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &rdram[addr]), @sizeOf(T));
    }
    else if (addr >= @enumToInt(MemBase.Bios) and addr < (@enumToInt(MemBase.Bios) + @enumToInt(MemSize.Bios))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &bios[addr - @enumToInt(MemBase.Bios)]), @sizeOf(T));
    } else {
        switch (addr) {
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
            0x1000_F130,
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
    } else {
        switch (addr) {
            0x1000_F180 => {
                if (T != u8) {
                    @panic("Unhandled write @ KPUTCHAR");
                }

                // info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (KPUTCHAR) = 0x{X}.", .{@typeName(T), addr, data});

                kputchar.write(@truncate(u8, data));
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
            0x1000_F500 => warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (Unknown) = 0x{X}.", .{@typeName(T), addr, data}),
            else => {
                err("  [Bus       ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X}.", .{@typeName(T), addr, data});

                assert(false);
            }
        }
    }
}
