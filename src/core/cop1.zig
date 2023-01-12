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

const math = std.math;

pub const Cond = enum(u2) {
    F  = 0,
    Eq = 1,
    Lt = 2,
    Le = 3,
};

const RegFile = struct {
    regs: [32]u32 = undefined,

    acc: u32 = undefined,

    /// Return FP register
    pub fn get(self: RegFile, idx: u5) f32 {
        return @bitCast(f32, self.regs[idx]);
    }

    /// Return Accumulator
    pub fn getAcc(self: RegFile) f32 {
        return @bitCast(f32, self.acc);
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

var cpcond1 = false;

/// Returns FPU control register
pub fn getControl(idx: u5) u32 {
    var data: u32 = 0;

    switch (idx) {
          31 => data |= @as(u32, @bitCast(u1, cpcond1)) << 23,
        else => {
            warn("[COP1      ] Control register read @ ${}.", .{idx});
        }
    }

    return data;
}

/// Returns CPCOND1
pub fn getCpcond1() bool {
    return cpcond1;
}

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
    return @truncate(u5, instr >> 6);
}

/// Get Rs field
fn getRs(instr: u32) u5 {
    return @truncate(u5, instr >> 11);
}

/// Get Rt field
fn getRt(instr: u32) u5 {
    return @truncate(u5, instr >> 16);
}

/// ADD
pub fn iAdd(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) + regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        std.debug.print("[COP1      ] ADD.S ${}, ${}, ${}; ${} = {}\n", .{fd, fs, ft, fd, res});
    }
}

/// ADD Accumulator
pub fn iAdda(instr: u32) void {
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) + regFile.get(ft);

    regFile.setAcc(res);

    if (doDisasm) {
        std.debug.print("[COP1      ] ADDA.S ${}, ${}; ACC = {}\n", .{fs, ft, res});
    }
}

/// C - Compare
pub fn iC(instr: u32, comptime cond: Cond) void {
    const fs = getRs(instr);
    const ft = getRt(instr);

    const s = regFile.get(fs);
    const t = regFile.get(ft);

    cpcond1 = switch (cond) {
        Cond.F  => false,
        Cond.Eq => s == t,
        Cond.Lt => s <  t,
        Cond.Le => s <= t,
    };

    if (doDisasm) {
        std.debug.print("[COP1      ] C.{s}.S ${}, ${}; ${} = {}, ${} = {}\n", .{@tagName(cond), fs, ft, fs, s, ft, t});
    }
}

/// ConVerT to Single
pub fn iCvts(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);

    regFile.set(fd, @intToFloat(f32, getRaw(fs)));

    if (doDisasm) {
        std.debug.print("[COP1      ] CVT.S.W ${}, ${}; ${} = {}\n", .{fd, fs, fd, regFile.get(fd)});
    }
}

/// ConVerT to Word
pub fn iCvtw(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);

    const s = getRaw(fs);

    if (@truncate(u8, s >> 23) >= 0x9D) {
        if ((s & (1 << 31)) != 0) {
            setRaw(fd, 0x8000_0000);
        } else {
            setRaw(fd, 0x7FFF_FFFF);
        }
    } else {
        setRaw(fd, @bitCast(u32, @floatToInt(i32, regFile.get(fs))));
    }

    if (doDisasm) {
        std.debug.print("[COP1      ] CVT.W.S ${}, ${}; ${} = 0x{X:0>8}\n", .{fd, fs, fd, getRaw(fd)});
    }
}

/// DIVide
pub fn iDiv(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) / regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        std.debug.print("[COP1      ] DIV.S ${}, ${}, ${}; ${} = {}\n", .{fd, fs, ft, fd, res});
    }
}

/// Multiply ADD
pub fn iMadd(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) * regFile.get(ft) + regFile.getAcc();

    regFile.set(fd, res);

    if (doDisasm) {
        std.debug.print("[COP1      ] MADD.S ${}, ${}, ${}; ${} = {}\n", .{fd, fs, ft, fd, res});
    }
}

/// MOVe
pub fn iMov(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);

    regFile.set(fd, regFile.get(fs));

    if (doDisasm) {
        std.debug.print("[COP1      ] MOV.S ${}, ${}; ${} = {}\n", .{fd, fs, fd, regFile.get(fs)});
    }
}

/// MULtiply
pub fn iMul(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) * regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        std.debug.print("[COP1      ] MUL.S ${}, ${}, ${}; ${} = {}\n", .{fd, fs, ft, fd, res});
    }
}

/// NEGate
pub fn iNeg(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);

    regFile.set(fd, -regFile.get(fs));

    if (doDisasm) {
        std.debug.print("[COP1      ] NEG.S ${}, ${}; ${} = {}\n", .{fd, fs, fd, regFile.get(fs)});
    }
}

/// SUB
pub fn iSub(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) - regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        std.debug.print("[COP1      ] SUB.S ${}, ${}, ${}; ${} = {}\n", .{fd, fs, ft, fd, res});
    }
}
