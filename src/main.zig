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
const gif      = @import("core/gif.zig");
const gs       = @import("core/gs.zig");
const iop      = @import("core/iop.zig");
const spu2     = @import("core/spu2.zig");
const timerIop = @import("core/timer_iop.zig");
const vif1     = @import("core/vif1.zig");

/// BIOS path
const biosPath = "moeFiles/bios.bin";
const cdvdPath = "moeFiles/atelier_iris.iso";
const elfPath  = "moeFiles/3stars.elf";

/// main()
pub fn main() void {
    info("   [moestation] BIOS file: {s}", .{biosPath});

    // Get allocator
    var allocator = std.heap.page_allocator;

    // Initialize submodules
    if (bus.init(allocator, biosPath, elfPath)) |_| {} else |e| switch (e) {
        error.FileNotFound => return err("  [moestation] Unable to find file.", .{}),
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

        while (i < 4) : (i += 1) {
            cpu.step();

            dmac.checkRunning();

            gif.step();
            vif1.step();
        }

        gs.step(4);
        spu2.step(4);

        iop.step();
        timerIop.step();
        cdvd.step();

        dmacIop.checkRunning();
    }
}
