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

// Memory arrays
var bios: []u8 = undefined; // BIOS ROM

/// Memory base addresses
const MemBase = enum(u32) {
    Bios = 0x1FC0_0000,
};

/// Memory sizes
const MemSize = enum(u32) {
    Bios = 0x40_0000,
};

/// Initializes the bus module
pub fn init(allocator: Allocator, biosPath: []const u8) !void {
    info("   [Bus       ] Loading BIOS image {s}...", .{biosPath});

    // Load BIOS file
    const biosFile = try openFile(biosPath, .{.mode = OpenMode.read_only});
    defer biosFile.close();

    bios = try biosFile.reader().readAllAlloc(allocator, @enumToInt(MemSize.Bios));

    info("   [Bus       ] Successfully loaded BIOS.", .{});
}

/// Deinitializes the bus module
pub fn deinit(allocator: Allocator) void {
    allocator.free(bios);
}

/// Reads data from the system bus
pub fn read(comptime T: type, addr: u32) T {
    assert(T == u8 or T == u16 or T == u32 or T == u64 or T == u128);

    var data: T = undefined;

    if (addr >= @enumToInt(MemBase.Bios) and addr < (@enumToInt(MemBase.Bios) + @enumToInt(MemSize.Bios))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &bios[addr - @enumToInt(MemBase.Bios)]), @sizeOf(T));
    } else {
        switch (addr) {
            0x1000_F130 => {
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

    switch (addr) {
        0x1000_F100, 0x1000_F120, 0x1000_F140, 0x1000_F150,
        0x1000_F500 => warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (Unknown) = 0x{X}.", .{@typeName(T), addr, data}),
        else => {
            err("  [Bus       ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X}.", .{@typeName(T), addr, data});

            assert(false);
        }
    }
}
