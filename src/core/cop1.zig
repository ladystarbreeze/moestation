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

const Cond = enum(u4) {
    F    = 0x0,
    Un   = 0x1,
    Eq   = 0x2,
    Ueq  = 0x3,
    Olt  = 0x4,
    Ult  = 0x5,
    Ole  = 0x6,
    Ule  = 0x7,
    Sf   = 0x8,
    Ngle = 0x9,
    Seq  = 0xA,
    Ngl  = 0xB,
    Lt   = 0xC,
    Nge  = 0xD,
    Le   = 0xE,
    Ngt  = 0xF,
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

/// ADD
pub fn iAdd(instr: u32) void {
    const fd = getRd(instr);
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) + regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        info("   [COP1      ] ADD.S ${}, ${}, ${}; ${} = {}", .{fd, fs, ft, fd, res});
    }
}

/// ADD Accumulator
pub fn iAdda(instr: u32) void {
    const fs = getRs(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) + regFile.get(ft);

    regFile.setAcc(res);

    if (doDisasm) {
        info("   [COP1      ] ADDA.S ${}, ${}; ACC = {}", .{fs, ft, res});
    }
}

/// C - Compare
pub fn iC(instr: u32, cond: u4) void {
    const fs = getRs(instr);
    const ft = getRt(instr);

    var cond_: u4 = 0;

    const s = regFile.get(fs);
    const t = regFile.get(ft);

    if (math.isNan(s) or math.isNan(t)) {
        if ((cond & 8) != 0) @panic("Invalid C.COND operation");

        cond_ = 1;
    } else {
        if (s <  t) cond_ |= 2;
        if (s == t) cond_ |= 4;
    }

    //fcr31.c = (cond & cond_) != 0;

    cpcond1 = (cond & cond_) != 0;

    if (doDisasm) {
        info("[COP1      ] C.{s}.S ${}, ${}", .{@tagName(@intToEnum(Cond, cond)), fs, ft});
    }
}

/// ConVerT to Single
pub fn iCvts(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);

    regFile.set(fd, @intToFloat(f32, getRaw(fs)));

    if (doDisasm) {
        info("   [COP1      ] CVT.S.W ${}, ${}; ${} = {}", .{fd, fs, fd, regFile.get(fd)});
    }
}

/// ConVerT to Word
pub fn iCvtw(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);

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
        info("   [COP1      ] CVT.W.S ${}, ${}; ${} = 0x{X:0>8}", .{fd, fs, fd, getRaw(fd)});
    }
}

/// DIVide
pub fn iDiv(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) / regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        info("   [COP1      ] DIV.S ${}, ${}, ${}; ${} = {}", .{fd, fs, ft, fd, res});
    }
}

/// Multiply ADD
pub fn iMadd(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) * regFile.get(ft) + regFile.getAcc();

    regFile.set(fd, res);

    if (doDisasm) {
        info("   [COP1      ] MADD.S ${}, ${}, ${}; ${} = {}", .{fd, fs, ft, fd, res});
    }
}

/// MOVe
pub fn iMov(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);

    regFile.set(fd, regFile.get(fs));

    if (doDisasm) {
        info("   [COP1      ] MOV.S ${}, ${}; ${} = {}", .{fd, fs, fd, regFile.get(fs)});
    }
}

/// MULtiply
pub fn iMul(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);
    const ft = getRt(instr);

    const res = regFile.get(fs) * regFile.get(ft);

    regFile.set(fd, res);

    if (doDisasm) {
        info("   [COP1      ] MUL.S ${}, ${}, ${}; ${} = {}", .{fd, fs, ft, fd, res});
    }
}

/// NEGate
pub fn iNeg(instr: u32) void {
    const fd = getRt(instr);
    const fs = getRt(instr);

    regFile.set(fd, -regFile.get(fs));

    if (doDisasm) {
        info("   [COP1      ] NEG.S ${}, ${}; ${} = {}", .{fd, fs, fd, regFile.get(fs)});
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
        info("   [COP1      ] SUB.S ${}, ${}, ${}; ${} = {}", .{fd, fs, ft, fd, res});
    }
}
