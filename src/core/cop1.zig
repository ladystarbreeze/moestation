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
const warn = std.log.warn;

const RegFile = struct {
    regs: [32]u32 = undefined,

    acc: u32 = undefined,

    /// Return FP register
    pub fn get(self: RegFile, idx: u5) f32 {
        return @bitCast(f32, self.regs[idx]);
    }

    /// Set FP register
    pub fn set(self: *RegFile, idx: u5, data: f32) void {
        self.regs[idx] = @bitCast(u32, data);
    }

    /// Set Accumulator
    pub fn setAcc(self: *RegFile, data: f32) void {
        self.acc = @bitCast(u32, data);
    }
};

const doDisasm = true;

var regFile: RegFile = RegFile{};

/// Returns raw FP register
pub fn getRaw(idx: u5) u32 {
    return regFile.regs[idx];
}

/// Sets FPU control register
pub fn setControl(idx: u5, data: u32) void {
    switch (idx) {
        else => {
            warn("[COP1      ] Control register write @ ${} = 0x{X:0>8}.", .{idx, data});
        }
    }
}

/// Sets raw FP register
pub fn setRaw(idx: u5, data: u32) void {
    regFile.regs[idx] = data;
}

/// Get Rd field
fn getRd(instr: u32) u5 {
    return @truncate(u5, instr >> 11);
}

/// Get Rs field
fn getRs(instr: u32) u5 {
    return @truncate(u5, instr >> 21);
}

/// Get Rt field
fn getRt(instr: u32) u5 {
    return @truncate(u5, instr >> 16);
}

/// ADD Accumulator
pub fn iAdda(instr: u32) void {
    const fs = getRt(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) + regFile.get(ft);

    regFile.setAcc(res);

    if (doDisasm) {
        info("   [COP1      ] ADDA.S ${}, ${}; ACC = {}", .{fs, ft, res});
    }
}
