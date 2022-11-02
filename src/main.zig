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
const bus      = @import("core/bus.zig");
const cdvd     = @import("core/cdvd.zig");
const cpu      = @import("core/cpu.zig");
const dmac     = @import("core/dmac.zig");
const dmacIop  = @import("core/dmac_iop.zig");
const iop      = @import("core/iop.zig");
const timerIop = @import("core/timer_iop.zig");

/// BIOS path
const biosPath = "moeFiles/bios.bin";
const cdvdPath = "moeFiles/atelier_iris.iso";

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

    if (cdvd.init(cdvdPath)) |_| {} else |e| switch (e) {
        error.FileNotFound => return err("  [moestation] Unable to find ISO.", .{}),
        else => return err("  [moestation] Unhandled error {}.", .{e})
    }

    defer cdvd.deinit();

    cpu.init();
    dmac.init();
    dmacIop.init();
    iop.init();

    while (true) {
        var i: i32 = 0;

        while (i < 8) : (i += 1) {
            cpu.step();

            dmac.checkRunning();
        }

        iop.step();
        timerIop.step();

        dmacIop.checkRunning();
    }
}
