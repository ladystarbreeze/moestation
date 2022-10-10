//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cop1.zig - EmotionEngine Core Floating-Point Unit
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const RegFile = struct {
    regs: [32]u32 = undefined,
};

var regFile: RegFile = RegFile{};

/// Returns raw FP register
pub fn getRaw(idx: u5) u32 {
    return regFile.regs[idx];
}

/// Sets raw FP register
pub fn setRaw(idx: u5, data: u32) void {
    regFile.regs[idx] = data;
}
