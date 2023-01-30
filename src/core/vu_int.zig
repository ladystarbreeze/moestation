//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! vu_int.zig - Vector Unit interpreter
//!

const std = @import("std");

const assert = std.debug.assert;

const Element = @import("vu.zig").Element;
const Vu = @import("vu.zig").Vu;

const doDisasm = true;

/// Get dest field
fn getDest(instr: u32) u4 {
    return @truncate(u4, instr >> 21);
}

/// Get dest string
fn getDestStr(dest: u4) []const u8 {
    return switch (dest) {
        0x0 => "",
        0x1 => "w",
        0x2 => "z",
        0x3 => "zw",
        0x4 => "y",
        0x5 => "yw",
        0x6 => "yz",
        0x7 => "yzw",
        0x8 => "x",
        0x9 => "xw",
        0xA => "xz",
        0xB => "xzw",
        0xC => "xy",
        0xD => "xyw",
        0xE => "xyz",
        0xF => "xyzw",
    };
}

/// Get d field
fn getRd(instr: u32) u5 {
    return @truncate(u5, instr >> 6);
}

/// Get t field
fn getRt(instr: u32) u5 {
    return @truncate(u5, instr >> 16);
}

/// Get s field
fn getRs(instr: u32) u5 {
    return @truncate(u5, instr >> 11);
}

/// floating-point ADDition
pub fn iAdd(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) + vu.getVfElement(f32, ft, e);

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] ADD.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, ft, destStr, fd, vd});
    }
}

/// ADD BroadCast
pub fn iAddbc(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    const bc = switch (@truncate(u2, instr)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

    const t = vu.getVfElement(f32, ft, bc);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) + t;

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] ADD{s}.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, fd, destStr, fs, destStr, ft, bcStr, fd, vd});
    }
}

/// floating-point ADDition with Q
pub fn iAddq(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) + vu.q;

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] ADDQ.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, fd, vd});
    }
}

/// DIVide
pub fn iDiv(vu: *Vu, instr: u32) void {
    const fsf = @intToEnum(Element, @as(u4, 1) << @truncate(u2, 3 - (getDest(instr)  & 3)));
    const ftf = @intToEnum(Element, @as(u4, 1) << @truncate(u2, 3 - (getDest(instr) >> 2)));

    const fs = getRs(instr);
    const ft = getRt(instr);

    vu.q = vu.getVfElement(f32, fs, fsf) / vu.getVfElement(f32, ft, ftf);

    if (doDisasm) {
        std.debug.print("[VU{}       ] DIV Q, VF[{}]{s}, VF[{}]{s}; Q = 0x{X:0>8}\n", .{vu.vuNum, fs, @tagName(fsf), ft, @tagName(ftf), @bitCast(u32, vu.q)});
    }
}

/// Integer ADDition
pub fn iIadd(vu: *Vu, instr: u32) void {
    const id = getRd(instr);
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(id < 16 and it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const res = vu.getVi(@truncate(u4, is)) +% vu.getVi(@truncate(u4, it));

    vu.setVi(@truncate(u4, id), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IADD VI[{}], VI[{}], VI[{}]; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, id, is, it, id, res});
    }
}

/// Integer Store
pub fn iIswr(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const addr = @as(u16, @truncate(u12, vu.getVi(@truncate(u4, is)))) << 4;
    const data = vu.getVi(@truncate(u4, it));

    var i: u12 = 0;
    while (i < 4) : (i += 1) {
        if ((dest & (@as(u4, 1) << (3 - @truncate(u2, i)))) != 0) {
            vu.writeData(u32, addr +% (i * 4), @as(u32, data));
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        std.debug.print("[VU{}       ] ISWR.{s} VI[{}]{s}, (VI[{}])\n", .{vu.vuNum, destStr, it, destStr, is});
    }
}

/// Multiply-ADD to Accumulator BroadCast
pub fn iMaddabc(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    const bc = switch (@truncate(u2, instr)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

    const t = vu.getVfElement(f32, ft, bc);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) * t + vu.acc.getElement(e);

            vu.acc.setElement(e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const acc = vu.acc.get();

        std.debug.print("[VU{}       ] MADDA{s}.{s} ACC{s}, VF[{}]{s}, VF[{}]{s}; ACC = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, destStr, fs, destStr, ft, bcStr, acc});
    }
}

/// Multiply-ADD BroadCast
pub fn iMaddbc(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    const bc = switch (@truncate(u2, instr)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

    const t = vu.getVfElement(f32, ft, bc);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) * t + vu.acc.getElement(e);

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MADD{s}.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, fd, destStr, fs, destStr, ft, bcStr, fd, vd});
    }
}

/// MOVE
pub fn iMove(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    if (dest & (1 << 0) != 0) {
        vu.setVfElement(f32, ft, Element.W, vu.getVfElement(f32, fs, Element.W));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(f32, ft, Element.Z, vu.getVfElement(f32, fs, Element.Z));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(f32, ft, Element.Y, vu.getVfElement(f32, fs, Element.Y));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVfElement(f32, ft, Element.X, vu.getVfElement(f32, fs, Element.X));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] MOVE.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, fs, destStr, ft, vt});
    }
}

/// Move and Rotate per word
pub fn iMr32(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    if (dest & (1 << 0) != 0) {
        vu.setVfElement(f32, ft, Element.X, vu.getVfElement(f32, fs, Element.W));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(f32, ft, Element.W, vu.getVfElement(f32, fs, Element.Z));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(f32, ft, Element.Z, vu.getVfElement(f32, fs, Element.Y));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVfElement(f32, ft, Element.Y, vu.getVfElement(f32, fs, Element.X));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] MR32.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, fs, destStr, ft, vt});
    }
}

/// floating-point MULtiply
pub fn iMul(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) * vu.getVfElement(f32, ft, e);

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MUL.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, ft, destStr, fd, vd});
    }
}

/// MULtiply to Accumulator BroadCast
pub fn iMulabc(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    const bc = switch (@truncate(u2, instr)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

    const t = vu.getVfElement(f32, ft, bc);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) * t;

            vu.acc.setElement(e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const acc = vu.acc.get();

        std.debug.print("[VU{}       ] MULA{s}.{s} ACC{s}, VF[{}]{s}, VF[{}]{s}; ACC = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, destStr, fs, destStr, ft, bcStr, acc});
    }
}

/// floating-point MULtiply with Q
pub fn iMulq(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) * vu.q;

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MULQ.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, fd, vd});
    }
}

/// No OPeration
pub fn iNop(vu: *Vu) void {
    if (doDisasm) {
        std.debug.print("[VU{}       ] NOP\n", .{vu.vuNum});
    }
}

/// Outer Product Multiply-SUBtract
pub fn iOpmsub(vu: *Vu, instr: u32) void {
    const dest = getDest(instr) & 0xE;

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    vu.setVfElement(f32, fd, Element.X, (vu.getVfElement(f32, fs, Element.Y) * vu.getVfElement(f32, ft, Element.Z)) + (vu.getVfElement(f32, fs, Element.Z) * vu.getVfElement(f32, ft, Element.Y)));
    vu.setVfElement(f32, fd, Element.Y, (vu.getVfElement(f32, fs, Element.Z) * vu.getVfElement(f32, ft, Element.X)) + (vu.getVfElement(f32, fs, Element.X) * vu.getVfElement(f32, ft, Element.Z)));
    vu.setVfElement(f32, fd, Element.Z, (vu.getVfElement(f32, fs, Element.X) * vu.getVfElement(f32, ft, Element.Y)) + (vu.getVfElement(f32, fs, Element.Y) * vu.getVfElement(f32, ft, Element.X)));

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] OPMSUB.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, ft, destStr, fd, vd});
    }
}

/// Outer Product MULtiply to Accumulator
pub fn iOpmula(vu: *Vu, instr: u32) void {
    const dest = getDest(instr) & 0xE;

    const ft = getRt(instr);
    const fs = getRs(instr);

    vu.acc.setElement(Element.X, (vu.getVfElement(f32, fs, Element.Y) * vu.getVfElement(f32, ft, Element.Z)) + (vu.getVfElement(f32, fs, Element.Z) * vu.getVfElement(f32, ft, Element.Y)));
    vu.acc.setElement(Element.Y, (vu.getVfElement(f32, fs, Element.Z) * vu.getVfElement(f32, ft, Element.X)) + (vu.getVfElement(f32, fs, Element.X) * vu.getVfElement(f32, ft, Element.Z)));
    vu.acc.setElement(Element.Z, (vu.getVfElement(f32, fs, Element.X) * vu.getVfElement(f32, ft, Element.Y)) + (vu.getVfElement(f32, fs, Element.Y) * vu.getVfElement(f32, ft, Element.X)));

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const acc = vu.acc.get();

        std.debug.print("[VU{}       ] OPMULA.{s} ACC{s}, VF[{}]{s}, VF[{}]{s}; ACC = 0x{X:0>32}\n", .{vu.vuNum, destStr, destStr, fs, destStr, ft, destStr, acc});
    }
}

/// Store Quadword with post-Increment
pub fn iSqi(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const is = getRs(instr);
    
    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});
        
        @panic("Index out of bounds");
    }

    const addr = @as(u16, @truncate(u12, vu.getVi(@truncate(u4, is)))) << 4;

    var i: u12 = 0;
    while (i < 4) : (i += 1) {
        if ((dest & (@as(u4, 1) << (3 - @truncate(u2, i)))) != 0) {
            const e = @intToEnum(Element, @as(u4, 1) << (3 - @truncate(u2, i)));

            vu.writeData(u32, addr +% (i * 4), vu.getVfElement(u32, ft, e));
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        std.debug.print("[VU{}       ] VSQI.{s} VF[{}]{s}, (VI[{}]++)\n", .{vu.vuNum, destStr, ft, destStr, is});
    }
}

/// SQuare RooT
pub fn iSqrt(vu: *Vu, instr: u32) void {
    const ftf = @intToEnum(Element, @as(u4, 1) << @truncate(u2, 3 - (getDest(instr)) >> 2));

    const ft = getRt(instr);

    vu.q = @sqrt(vu.getVfElement(f32, ft, ftf));

    if (doDisasm) {
        std.debug.print("[VU{}       ] SQRT Q, VF[{}]{s}; Q = 0x{X:0>8}\n", .{vu.vuNum, ft, @tagName(ftf), @bitCast(u32, vu.q)});
    }
}

/// floating-point SUBtract
pub fn iSub(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) - vu.getVfElement(f32, ft, e);

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] SUB.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, ft, destStr, fd, vd});
    }
}

/// WAIT Q
pub fn iWaitq(vu: *Vu) void {
    if (doDisasm) {
        std.debug.print("[VU{}       ] VWAITQ\n", .{vu.vuNum});
    }
}
