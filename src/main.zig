//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! main.zig
//!

const std = @import("std");

const err  = std.log.err;
const info = std.log.info;

// Submodules
const bus = @import("core/bus.zig");
const cpu = @import("core/cpu.zig");

/// BIOS path
const biosPath = "moeFiles/bios.bin";

/// main()
pub fn main() void {
    info("   [moestation] BIOS file: {s}", .{biosPath});

    // Get allocator
    var allocator = std.heap.page_allocator;

    // Initialize submodules
    if (bus.init(allocator, biosPath)) |_| {} else |e| switch (e) {
        error.FileNotFound => return err("  [moestation] Unable to find BIOS file.", .{}),
        else => return err("  [moestation] Unhandled error {}.", .{e})
    }

    defer bus.deinit(allocator);

    cpu.init();

    while (true) {
        cpu.step();
    }
}
