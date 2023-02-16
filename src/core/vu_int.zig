//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! vu_int.zig - Vector Unit interpreter
//!

const std = @import("std");

const assert = std.debug.assert;

const gif = @import("gif.zig");

const ActivePath = gif.ActivePath;

const vif1 = @import("vif1.zig");

const Element = @import("vu.zig").Element;
const Vu      = @import("vu.zig").Vu;
const VuState = @import("vu.zig").VuState;

const LowerOp = enum(u7) {
    Lq      = 0x00,
    Sq      = 0x01,
    Ilw     = 0x04,
    Isw     = 0x05,
    Iaddiu  = 0x08,
    Isubiu  = 0x09,
    Fcset   = 0x11,
    Fcand   = 0x12,
    Fmand   = 0x1A,
    B       = 0x20,
    Bal     = 0x21,
    Jr      = 0x24,
    Jalr    = 0x25,
    Ibne    = 0x29,
    Ibgtz   = 0x2D,
    Special = 0x40,
};

const LowerOpSpecial = enum(u6) {
    Iadd  = 0x30,
    Iaddi = 0x32,
    Iand  = 0x34,
    Ior   = 0x35,
};

const LowerOpSpecial2 = enum(u7) {
    Xtop   = 0x28,
    Xgkick = 0x2C,
    Move   = 0x30,
    Lqi    = 0x34,
    Sqi    = 0x35,
    Div    = 0x38,
    Waitq  = 0x3B,
    Mfir   = 0x3D,
    Ilwr   = 0x3E,
    Iswr   = 0x3F,
};

const UpperOp = enum(u7) {
    Addbc  = 0x00,
    Subbc  = 0x04,
    Maddbc = 0x08,
    Maxbc  = 0x10,
    Mulq   = 0x1C,
    Addi   = 0x22,
    Add    = 0x28,
    Madd   = 0x29,
    Mul    = 0x2A,
    Sub    = 0x2C,
};

const UpperOpSpecial = enum(u7) {
    Maddabc = 0x08,
    Ftoi0   = 0x14,
    Ftoi4   = 0x15,
    Mulabc  = 0x18,
    Clip    = 0x1F,
    Nop     = 0x2F,
};

const doDisasm = true;

/// Get dest field
fn getDest(instr: u32) u4 {
    return @truncate(u4, instr >> 21);
}

/// Get dest string
fn getDestStr(dest: u4) []const u8 {
    return switch (dest) {
        0x0 => "nop",
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

/// Decodes and executes a lower instruction
pub fn executeLower(vu: *Vu, instr: u32) void {
    const opcode = @truncate(u7, instr >> 25);

    switch (opcode) {
        @enumToInt(LowerOp.Lq     ) => iLq(vu, instr),
        @enumToInt(LowerOp.Sq     ) => iSq(vu, instr),
        @enumToInt(LowerOp.Ilw    ) => iIlw(vu, instr),
        @enumToInt(LowerOp.Isw    ) => iIsw(vu, instr),
        @enumToInt(LowerOp.Iaddiu ) => iIaddiu(vu, instr),
        @enumToInt(LowerOp.Isubiu ) => iIsubiu(vu, instr),
        @enumToInt(LowerOp.Fcset  ) => iFcset(vu, instr),
        @enumToInt(LowerOp.Fcand  ) => iFcand(vu, instr),
        @enumToInt(LowerOp.Fmand  ) => iFmand(vu, instr),
        @enumToInt(LowerOp.B      ) => iB(vu, instr),
        @enumToInt(LowerOp.Bal    ) => iBal(vu, instr),
        @enumToInt(LowerOp.Jr     ) => iJr(vu, instr),
        @enumToInt(LowerOp.Jalr   ) => iJalr(vu, instr),
        @enumToInt(LowerOp.Ibne   ) => iIbne(vu, instr),
        @enumToInt(LowerOp.Ibgtz  ) => iIbgtz(vu, instr),
        @enumToInt(LowerOp.Special) => {
            const funct = @truncate(u6, instr);

            if ((funct >> 2) == 0xF) {
                const funct2 = (@truncate(u6, instr >> 6) << 2) | (funct & 3);

                switch (funct2) {
                    @enumToInt(LowerOpSpecial2.Xtop  ) => iXtop(vu, instr),
                    @enumToInt(LowerOpSpecial2.Xgkick) => iXgkick(vu, instr),
                    @enumToInt(LowerOpSpecial2.Move  ) => iMove(vu, instr),
                    @enumToInt(LowerOpSpecial2.Lqi   ) => iLqi(vu, instr),
                    @enumToInt(LowerOpSpecial2.Sqi   ) => iSqi(vu, instr),
                    @enumToInt(LowerOpSpecial2.Div   ) => iDiv(vu, instr),
                    @enumToInt(LowerOpSpecial2.Waitq ) => iWaitq(vu),
                    @enumToInt(LowerOpSpecial2.Mfir  ) => iMfir(vu, instr),
                    @enumToInt(LowerOpSpecial2.Ilwr  ) => iIlwr(vu, instr),
                    @enumToInt(LowerOpSpecial2.Iswr  ) => iIswr(vu, instr),
                    else => {
                        std.debug.print("[VU{}       ] Unhandled 11-bit lower instruction 0x{X:0>2} (0x{X:0>8})\n", .{vu.vuNum, funct2, instr});

                        @panic("Unhandled lower instruction");
                    }
                }
            } else {
                switch (funct) {
                    @enumToInt(LowerOpSpecial.Iadd ) => iIadd(vu, instr),
                    @enumToInt(LowerOpSpecial.Iaddi) => iIaddi(vu, instr),
                    @enumToInt(LowerOpSpecial.Iand ) => iIand(vu, instr),
                    @enumToInt(LowerOpSpecial.Ior  ) => iIor(vu, instr),
                    else => {
                        std.debug.print("[VU{}       ] Unhandled lower instruction 0x{X:0>2} (0x{X:0>8})\n", .{vu.vuNum, funct, instr});

                        @panic("Unhandled lower instruction");
                    }
                }
            }
        },
        else => {
            std.debug.print("[VU{}       ] Unhandled lower instruction  0x{X:0>2} (0x{X:0>8})\n", .{vu.vuNum, opcode, instr});

            @panic("Unhandled lower instruction");
        }
    }
}

/// Decodes and executes an upper instruction
pub fn executeUpper(vu: *Vu, instr: u32) void {
    const opcode = @truncate(u6, instr);

    if ((opcode >> 2) == 0xF) {
        const funct = (@truncate(u6, instr >> 6) << 2) | (opcode & 3);

        switch (funct) {
            @enumToInt(UpperOpSpecial.Maddabc) ... @enumToInt(UpperOpSpecial.Maddabc) + 3 => iMaddabc(vu, instr),
            @enumToInt(UpperOpSpecial.Ftoi0  ) => iFtoi0(vu, instr),
            @enumToInt(UpperOpSpecial.Ftoi4  ) => iFtoi4(vu, instr),
            @enumToInt(UpperOpSpecial.Mulabc ) ... @enumToInt(UpperOpSpecial.Mulabc ) + 3 => iMulabc(vu, instr),
            @enumToInt(UpperOpSpecial.Clip   ) => iClip(vu, instr),
            @enumToInt(UpperOpSpecial.Nop    ) => iNop(vu),
            else => {
                std.debug.print("[VU{}       ] Unhandled 11-bit upper instruction 0x{X:0>2} (0x{X:0>8})\n", .{vu.vuNum, funct, instr});

                @panic("Unhandled upper instruction");
            }
        }
    } else {
        switch (opcode) {
            @enumToInt(UpperOp.Addbc ) ... @enumToInt(UpperOp.Addbc ) + 3 => iAddbc(vu, instr),
            @enumToInt(UpperOp.Subbc ) ... @enumToInt(UpperOp.Subbc ) + 3 => iSubbc(vu, instr),
            @enumToInt(UpperOp.Maddbc) ... @enumToInt(UpperOp.Maddbc) + 3 => iMaddbc(vu, instr),
            @enumToInt(UpperOp.Maxbc ) ... @enumToInt(UpperOp.Maxbc ) + 3 => iMaxbc(vu, instr),
            @enumToInt(UpperOp.Mulq  ) => iMulq(vu, instr),
            @enumToInt(UpperOp.Addi  ) => iAddi(vu, instr),
            @enumToInt(UpperOp.Add   ) => iAdd(vu, instr),
            @enumToInt(UpperOp.Madd  ) => iMadd(vu, instr),
            @enumToInt(UpperOp.Mul   ) => iMul(vu, instr),
            @enumToInt(UpperOp.Sub   ) => iSub(vu, instr),
            else => {
                std.debug.print("[VU{}       ] Unhandled upper instruction 0x{X:0>2} (0x{X:0>8})\n", .{vu.vuNum, opcode, instr});

                @panic("Unhandled upper instruction");
            }
        }
    }
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

/// floating-point ADDition with I
pub fn iAddi(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) + vu.i;

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] ADDI.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, fd, vd});
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

/// Branch
pub fn iB(vu: *Vu, instr: u32) void {
    const target = vu.pc +% (@bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr)))) << 3);

    vu.doBranch(target, true, 0);

    if (doDisasm) {
        std.debug.print("[VU{}       ] B 0x{X:0>4}\n", .{vu.vuNum, target});
    }
}

/// Branch And Link
pub fn iBal(vu: *Vu, instr: u32) void {
    const it = getRt(instr);

    if (it >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const target = vu.pc +% (@bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr)))) << 3);

    vu.doBranch(target, true, @truncate(u4, it));

    if (doDisasm) {
        std.debug.print("[VU{}       ] BAL VI[{}], 0x{X:0>4}; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, it, target, it, vu.npc});
    }
}

/// CLIPping judgement
pub fn iClip(vu: *Vu, instr: u32) void {
    const ft = getRt(instr);
    const fs = getRs(instr);

    const w = @fabs(vu.getVfElement(f32, ft, Element.W));

    const x = vu.getVfElement(f32, fs, Element.X);
    const y = vu.getVfElement(f32, fs, Element.Y);
    const z = vu.getVfElement(f32, fs, Element.Z);

    // Move previous judgements up
    vu.cf <<= 6;

    vu.cf |= @as(u24, @bitCast(u1, x >  w));
    vu.cf |= @as(u24, @bitCast(u1, x < -w)) << 1;
    vu.cf |= @as(u24, @bitCast(u1, y >  w)) << 2;
    vu.cf |= @as(u24, @bitCast(u1, y < -w)) << 3;
    vu.cf |= @as(u24, @bitCast(u1, z >  w)) << 4;
    vu.cf |= @as(u24, @bitCast(u1, z < -w)) << 5;

    if (doDisasm) {
        std.debug.print("[VU{}       ] CLIPw.xyz VF[{}].xyz, VF[{}].w; $CF = 0b{b:0>24}\n", .{vu.vuNum, fs, ft, vu.cf});
    }
}

/// DIVide
pub fn iDiv(vu: *Vu, instr: u32) void {
    const fsf = switch (@truncate(u2, getDest(instr) & 3)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

    const ftf = switch (@truncate(u2, getDest(instr) >> 2)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

    const fs = getRs(instr);
    const ft = getRt(instr);

    const s = vu.getVfElement(f32, fs, fsf);
    const t = vu.getVfElement(f32, ft, ftf);

    if (t == 0.0) {
        std.debug.print("[VU{}       ] DIV by 0\n", .{vu.vuNum});

        //@panic("DIV by 0");

        vu.q = if ((@bitCast(u32, s) >> 31) == (@bitCast(u32, t) >> 31)) @bitCast(f32, @as(u32, 0xFF7F_FFFF)) else @bitCast(f32, @as(u32, 0x7F7F_FFFF));
    } else {
        vu.q = s / t;
    }

    if (doDisasm) {
        std.debug.print("[VU{}       ] DIV Q, VF[{}]{s}, VF[{}]{s}; Q = 0x{X:0>8}\n", .{vu.vuNum, fs, @tagName(fsf), ft, @tagName(ftf), @bitCast(u32, vu.q)});
    }
}

/// Flag (Clipping) AND
pub fn iFcand(vu: *Vu, instr: u32) void {
    const imm24 = @truncate(u24, instr);

    vu.setVi(1, @as(u16, @bitCast(u1, (vu.cf & imm24) != 0)));

    if (doDisasm) {
        std.debug.print("[VU{}       ] FCAND VI[1], 0x{X:0>6}; VI[1] = 0x{X:0>3}\n", .{vu.vuNum, imm24, vu.getVi(1)});
    }
}

/// Flag (Clipping) SET
pub fn iFcset(vu: *Vu, instr: u32) void {
    const imm24 = @truncate(u24, instr);

    vu.cf = imm24;

    if (doDisasm) {
        std.debug.print("[VU{}       ] FCSET 0x{X:0>6}\n", .{vu.vuNum, imm24});
    }
}

/// Flag (MAC) AND
pub fn iFmand(vu: *Vu, instr: u32) void {
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    // TODO: implement MAC flags!!!!!
    vu.setVi(@truncate(u4, it), (0 & vu.getVi(@truncate(u4, is))));

    if (doDisasm) {
        std.debug.print("[VU{}       ] FMAND VI[{}], VI[{}]; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, it, is, it, vu.getVi(@truncate(u4, it))});
    }
}

/// Float to 32:0 fixed-point integer
pub fn iFtoi0(vu: *Vu, instr: u32) void {
    std.debug.print("FTOI0!\n", .{});

    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    if (dest & (1 << 0) != 0) {
        std.debug.print("w: {}\n", .{vu.getVfElement(f32, fs, Element.W)});
        vu.setVfElement(u32, ft, Element.W, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.W)) * 1.0)))));
    }
    if (dest & (1 << 1) != 0) {
        std.debug.print("z: {}\n", .{vu.getVfElement(f32, fs, Element.Z)});
        vu.setVfElement(u32, ft, Element.Z, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.Z)) * 1.0)))));
    }
    if (dest & (1 << 2) != 0) {
        std.debug.print("y: {}\n", .{vu.getVfElement(f32, fs, Element.Y)});
        vu.setVfElement(u32, ft, Element.Y, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.Y)) * 1.0)))));
    }
    if (dest & (1 << 3) != 0) {
        std.debug.print("x: {}\n", .{vu.getVfElement(f32, fs, Element.X)});
        vu.setVfElement(u32, ft, Element.X, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.X)) * 1.0)))));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] FTOI0.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, fs, destStr, ft, vt});
    }
}

/// Float to 28:4 fixed-point integer
pub fn iFtoi4(vu: *Vu, instr: u32) void {
    std.debug.print("FTOI4!\n", .{});

    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    if (dest & (1 << 0) != 0) {
        const w = vu.getVfElement(u32, fs, Element.W);

        if (w == 0x7F80_0000 or w == 0xFF80_0000 or (w & ~@as(u32, 1 << 31)) == 0x7FFF_FFFF) {
            std.debug.print("Invalid floating-point value 0x{X:0>8}\n", .{w});
        } else {
            std.debug.print("w: {}\n", .{vu.getVfElement(f32, fs, Element.W)});
            vu.setVfElement(u32, ft, Element.W, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.W)) * 16.0)))));
        }
    }
    if (dest & (1 << 1) != 0) {
        const z = vu.getVfElement(u32, fs, Element.Z);

        if (z == 0x7F80_0000 or z == 0xFF80_0000 or (z & ~@as(u32, 1 << 31)) == 0x7FFF_FFFF) {
            std.debug.print("Invalid floating-point value 0x{X:0>8}\n", .{z});
        } else {
            std.debug.print("z: {}\n", .{vu.getVfElement(f32, fs, Element.Z)});
            vu.setVfElement(u32, ft, Element.Z, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.Z)) * 16.0)))));
        }
    }
    if (dest & (1 << 2) != 0) {
        std.debug.print("y: {}\n", .{vu.getVfElement(f32, fs, Element.Y)});
        vu.setVfElement(u32, ft, Element.Y, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.Y)) * 16.0)))));
    }
    if (dest & (1 << 3) != 0) {
        std.debug.print("x: {}\n", .{vu.getVfElement(f32, fs, Element.X)});
        vu.setVfElement(u32, ft, Element.X, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.X)) * 16.0)))));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] FTOI4.{s} VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, fs, destStr, ft, vt});
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

    const res = vu.getVi(@truncate(u4, is)) + vu.getVi(@truncate(u4, it));

    vu.setVi(@truncate(u4, id), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IADD VI[{}], VI[{}], VI[{}]; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, id, is, it, id, res});
    }
}

/// Integer ADDition Immediate
pub fn iIaddi(vu: *Vu, instr: u32) void {
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const imm = @bitCast(u16, @as(i16, @bitCast(i5, getRd(instr))));

    const res = vu.getVi(@truncate(u4, is)) +% imm;

    vu.setVi(@truncate(u4, it), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IADDI VI[{}], VI[{}], {}; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, it, is, imm, it, res});
    }
}

/// Integer ADDition Immediate Unsigned
pub fn iIaddiu(vu: *Vu, instr: u32) void {
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const imm = @truncate(u15, ((instr >> 10) & 0x7800) | (instr & 0x7FF));

    const res = vu.getVi(@truncate(u4, is)) +% imm;

    vu.setVi(@truncate(u4, it), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IADDIU VI[{}], VI[{}], {}; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, it, is, @bitCast(i15, imm), it, res});
    }
}

/// Integer AND
pub fn iIand(vu: *Vu, instr: u32) void {
    const id = getRd(instr);
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(id < 16 and it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const res = vu.getVi(@truncate(u4, is)) & vu.getVi(@truncate(u4, it));

    vu.setVi(@truncate(u4, id), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IAND VI[{}], VI[{}], VI[{}]; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, id, is, it, id, res});
    }
}

/// Integer Branch if Greater Than Zero
pub fn iIbgtz(vu: *Vu, instr: u32) void {
    const is = getRs(instr);

    if (is > 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const target = vu.pc +% (@bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr)))) << 3);

    const s = vu.getVi(@truncate(u4, is));

    vu.doBranch(target, @bitCast(i16, s) > 0, 0);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IBGTZ VI[{}], 0x{X:0>4}; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, is, target, is, s});
    }
}

/// Integer Branch if Not Equal
pub fn iIbne(vu: *Vu, instr: u32) void {
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const target = vu.pc +% (@bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr)))) << 3);

    const t = vu.getVi(@truncate(u4, it));
    const s = vu.getVi(@truncate(u4, is));

    vu.doBranch(target, t != s, 0);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IBNE VI[{}], VI[{}], 0x{X:0>4}; VI[{}] = 0x{X:0>3}, VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, it, is, target, it, t, is, s});
    }
}

/// Integer Load Word
pub fn iIlw(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const is = getRs(instr);

    if (!(is < 16 and it < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const imm = @bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr))));

    const addr = (vu.getVi(@truncate(u4, is)) +% imm) << 4;
    const data = vu.readData(u128, addr);

    if (dest & (1 << 0) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 96));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 64));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 32));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 0));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVi(@truncate(u4, it));

        std.debug.print("[VU{}       ] ILW.{s} VI[{}]{s}, {}(VI[{}]); VI[{}] = [0x{X:0>4}] = 0x{X:0>3}\n", .{vu.vuNum, destStr, it, destStr, @bitCast(i16, imm), is, it, addr, vt});
    }
}

/// Integer Load Word Register
pub fn iIlwr(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const is = getRs(instr);

    if (!(is < 16 and it < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const addr = vu.getVi(@truncate(u4, is)) << 4;
    const data = vu.readData(u128, addr);

    if (dest & (1 << 0) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 96));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 64));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 32));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVi(@truncate(u4, it), @truncate(u16, data >> 0));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVi(@truncate(u4, it));

        std.debug.print("[VU{}       ] ILWR.{s} VI[{}]{s}, (VI[{}]); VI[{}] = [0x{X:0>4}] = 0x{X:0>3}\n", .{vu.vuNum, destStr, it, destStr, is, it, addr, vt});
    }
}

/// Integer OR
pub fn iIor(vu: *Vu, instr: u32) void {
    const id = getRd(instr);
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(id < 16 and it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const res = vu.getVi(@truncate(u4, is)) | vu.getVi(@truncate(u4, it));

    vu.setVi(@truncate(u4, id), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] IOR VI[{}], VI[{}], VI[{}]; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, id, is, it, id, res});
    }
}

/// Integer SUBtract Immediate Unsigned
pub fn iIsubiu(vu: *Vu, instr: u32) void {
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const imm = @truncate(u15, ((instr >> 10) & 0x7800) | (instr & 0x7FF));

    const res = vu.getVi(@truncate(u4, is)) -% imm;

    vu.setVi(@truncate(u4, it), res);

    if (doDisasm) {
        std.debug.print("[VU{}       ] ISUBIU VI[{}], VI[{}], {}; VI[{}] = 0x{X:0>3}\n", .{vu.vuNum, it, is, @bitCast(i15, imm), it, res});
    }
}

/// Integer Store Word
pub fn iIsw(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const is = getRs(instr);

    if (!(is < 16 and it < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const imm = @bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr))));

    const addr = (vu.getVi(@truncate(u4, is)) +% imm) << 4;
    const data = @as(u32, vu.getVi(@truncate(u4, it)));

    std.debug.print("ISW: VI[{}] = 0x{X:0>3}, imm = {}, addr = 0x{X:0>3}\n", .{is, vu.getVi(@truncate(u4, is)), @bitCast(i16, imm), addr});

    if (dest & (1 << 0) != 0) {
        vu.writeData(u32, addr + 12, data);
    }
    if (dest & (1 << 1) != 0) {
        vu.writeData(u32, addr + 8, data);
    }
    if (dest & (1 << 2) != 0) {
        vu.writeData(u32, addr + 4, data);
    }
    if (dest & (1 << 3) != 0) {
        vu.writeData(u32, addr + 0, data);
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVi(@truncate(u4, it));

        std.debug.print("[VU{}       ] ISW.{s} VI[{}]{s}, {}(VI[{}]); [0x{X:0>4}] = 0x{X:0>3}\n", .{vu.vuNum, destStr, it, destStr, @bitCast(i16, imm), is, addr, vt});
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

    const addr = vu.getVi(@truncate(u4, is)) << 4;
    const data = @as(u32, vu.getVi(@truncate(u4, it)));

    if (dest & (1 << 0) != 0) {
        vu.writeData(u32, addr + 12, data);
    }
    if (dest & (1 << 1) != 0) {
        vu.writeData(u32, addr + 8, data);
    }
    if (dest & (1 << 2) != 0) {
        vu.writeData(u32, addr + 4, data);
    }
    if (dest & (1 << 3) != 0) {
        vu.writeData(u32, addr + 0, data);
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        std.debug.print("[VU{}       ] ISWR.{s} VI[{}]{s}, (VI[{}])\n", .{vu.vuNum, destStr, it, destStr, is});
    }
}

/// Jump And Link Register
pub fn iJalr(vu: *Vu, instr: u32) void {
    const it = getRt(instr);
    const is = getRs(instr);

    if (!(it < 16 and is < 16)) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const target = vu.getVi(@truncate(u4, is)) * 8;

    vu.doBranch(target, true, @truncate(u4, it));

    if (doDisasm) {
        std.debug.print("[VU{}       ] JALR VI[{}], VI[{}]; VI[{}] = 0x{X:0>3}, PC = 0x{X:0>3}\n", .{vu.vuNum, it, is, it, vu.getVi(@truncate(u4, it)), target});
    }
}

/// Jump Register
pub fn iJr(vu: *Vu, instr: u32) void {
    const is = getRs(instr);

    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const target = vu.getVi(@truncate(u4, is)) * 8;

    vu.doBranch(target, true, 0);

    if (doDisasm) {
        std.debug.print("[VU{}       ] JR VI[{}]; PC = 0x{X:0>3}\n", .{vu.vuNum, is, target});
    }
}

/// Load Quadword
pub fn iLq(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const is = getRs(instr);

    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const imm = @bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr))));

    const addr = (vu.getVi(@truncate(u4, is)) +% imm) << 4;
    const data = vu.readData(u128, addr);

    if (dest & (1 << 0) != 0) {
        vu.setVfElement(u32, ft, Element.W, @truncate(u32, data >> 96));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(u32, ft, Element.Z, @truncate(u32, data >> 64));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(u32, ft, Element.Y, @truncate(u32, data >> 32));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVfElement(u32, ft, Element.X, @truncate(u32, data >> 0));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] LQ.{s} VF[{}]{s}, {}(VI[{}]); VF[{}] = [0x{X:0>4}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, @bitCast(i16, imm), is, ft, addr, vt});
    }
}

/// Load Quadword Increment
pub fn iLqi(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const is = getRs(instr);

    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const addr = vu.getVi(@truncate(u4, is)) << 4;
    const data = vu.readData(u128, addr);

    if (dest & (1 << 0) != 0) {
        vu.setVfElement(u32, ft, Element.W, @truncate(u32, data >> 96));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(u32, ft, Element.Z, @truncate(u32, data >> 64));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(u32, ft, Element.Y, @truncate(u32, data >> 32));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVfElement(u32, ft, Element.X, @truncate(u32, data >> 0));
    }

    vu.setVi(@truncate(u4, is), vu.getVi(@truncate(u4, is)) + 1);

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] LQI.{s} VF[{}]{s}, (VI[{}]++); VF[{}] = [0x{X:0>4}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, is, ft, addr, vt});
    }
}

/// floating-point Multiply ADD
pub fn iMadd(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = vu.getVfElement(f32, fs, e) * vu.getVfElement(f32, ft, e) + vu.acc.getElement(e);

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MADD.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fd, destStr, fs, destStr, ft, destStr, fd, vd});
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

/// MAX BroadCast
pub fn iMaxbc(vu: *Vu, instr: u32) void {
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
            const s = vu.getVfElement(f32, fs, e);

            vu.setVfElement(f32, fd, e, if (s > t) s else t);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MAX{s}.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, fd, destStr, fs, destStr, ft, bcStr, fd, vd});
    }
}

/// Move From Integer Register
pub fn iMfir(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const is = getRs(instr);

    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});

        @panic("Index out of bounds");
    }

    const s = @bitCast(u32, @as(i32, @bitCast(i16, vu.getVi(@truncate(u4, is)))));

    if (dest & (1 << 0) != 0) {
        vu.setVfElement(u32, ft, Element.W, s);
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(u32, ft, Element.Z, s);
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(u32, ft, Element.Y, s);
    }
    if (dest & (1 << 3) != 0) {
        vu.setVfElement(u32, ft, Element.X, s);
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vt = vu.getVf(ft);

        std.debug.print("[VU{}       ] MFIR.{s} VF[{}]{s}, VI[{}]; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, ft, destStr, is, ft, vt});
    }
}

/// MINI BroadCast
pub fn iMinibc(vu: *Vu, instr: u32) void {
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
            const s = vu.getVfElement(f32, fs, e);

            vu.setVfElement(f32, fd, e, if (s < t) s else t);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MINI{s}.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, fd, destStr, fs, destStr, ft, bcStr, fd, vd});
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
        vu.setVfElement(f32, ft, Element.W, vu.getVfElement(f32, fs, Element.X));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(f32, ft, Element.Z, vu.getVfElement(f32, fs, Element.W));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(f32, ft, Element.Y, vu.getVfElement(f32, fs, Element.Z));
    }
    if (dest & (1 << 3) != 0) {
        vu.setVfElement(f32, ft, Element.X, vu.getVfElement(f32, fs, Element.Y));
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

/// MULtiply BroadCast
pub fn iMulbc(vu: *Vu, instr: u32) void {
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
            const res = vu.getVfElement(f32, fs, e) * t;

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] MUL{s}.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, fd, destStr, fs, destStr, ft, bcStr, fd, vd});
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

    vu.setVfElement(f32, fd, Element.X, vu.acc.getElement(Element.X) - vu.getVfElement(f32, fs, Element.Y) * vu.getVfElement(f32, ft, Element.Z));
    vu.setVfElement(f32, fd, Element.Y, vu.acc.getElement(Element.Y) - vu.getVfElement(f32, fs, Element.Z) * vu.getVfElement(f32, ft, Element.X));
    vu.setVfElement(f32, fd, Element.Z, vu.acc.getElement(Element.Z) - vu.getVfElement(f32, fs, Element.X) * vu.getVfElement(f32, ft, Element.Y));

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

    vu.acc.setElement(Element.X, (vu.getVfElement(f32, fs, Element.Y) * vu.getVfElement(f32, ft, Element.Z)));
    vu.acc.setElement(Element.Y, (vu.getVfElement(f32, fs, Element.Z) * vu.getVfElement(f32, ft, Element.X)));
    vu.acc.setElement(Element.Z, (vu.getVfElement(f32, fs, Element.X) * vu.getVfElement(f32, ft, Element.Y)));

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const acc = vu.acc.get();

        std.debug.print("[VU{}       ] OPMULA.{s} ACC{s}, VF[{}]{s}, VF[{}]{s}; ACC = 0x{X:0>32}\n", .{vu.vuNum, destStr, destStr, fs, destStr, ft, destStr, acc});
    }
}

/// Store Quadword
pub fn iSq(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const fs = getRs(instr);
    
    if (it >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});
        
        @panic("Index out of bounds");
    }

    const imm = @bitCast(u16, @as(i16, @bitCast(i11, @truncate(u11, instr))));

    const addr = (vu.getVi(@truncate(u4, it)) +% imm) << 4;

    std.debug.print("SQ: VI[{}] = 0x{X:0>3}, imm = {}, addr = 0x{X:0>3}\n", .{it, vu.getVi(@truncate(u4, it)), @bitCast(i16, imm), addr});

    if (dest & (1 << 0) != 0) {
        vu.writeData(u32, addr + 12, vu.getVfElement(u32, fs, Element.W));
    }
    if (dest & (1 << 1) != 0) {
        vu.writeData(u32, addr + 8, vu.getVfElement(u32, fs, Element.Z));
    }
    if (dest & (1 << 2) != 0) {
        vu.writeData(u32, addr + 4, vu.getVfElement(u32, fs, Element.Y));
    }
    if (dest & (1 << 3) != 0) {
        vu.writeData(u32, addr + 0, vu.getVfElement(u32, fs, Element.X));
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        std.debug.print("[VU{}       ] SQ.{s} VF[{}]{s}, {}(VI[{}]); [0x{X:0>4}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fs, destStr, @bitCast(i16, imm), it, addr, vu.getVf(fs)});
    }
}

/// Store Quadword with post-Increment
pub fn iSqi(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const fs = getRs(instr);
    
    if (it >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});
        
        @panic("Index out of bounds");
    }

    const addr = vu.getVi(@truncate(u4, it)) << 4;

    if (dest & (1 << 0) != 0) {
        vu.writeData(u32, addr + 12, vu.getVfElement(u32, fs, Element.W));
    }
    if (dest & (1 << 1) != 0) {
        vu.writeData(u32, addr + 8, vu.getVfElement(u32, fs, Element.Z));
    }
    if (dest & (1 << 2) != 0) {
        vu.writeData(u32, addr + 4, vu.getVfElement(u32, fs, Element.Y));
    }
    if (dest & (1 << 3) != 0) {
        vu.writeData(u32, addr + 0, vu.getVfElement(u32, fs, Element.X));
    }

    vu.setVi(@truncate(u4, it), vu.getVi(@truncate(u4, it)) + 1);

    if (doDisasm) {
        const destStr = getDestStr(dest);

        std.debug.print("[VU{}       ] SQI.{s} VF[{}]{s}, (VI[{}]++); [0x{X:0>4}] = 0x{X:0>32}\n", .{vu.vuNum, destStr, fs, destStr, it, addr, vu.getVf(fs)});
    }
}

/// SQuare RooT
pub fn iSqrt(vu: *Vu, instr: u32) void {
    const ftf = switch (@truncate(u2, getDest(instr) >> 2)) {
        0 => Element.X,
        1 => Element.Y,
        2 => Element.Z,
        3 => Element.W,
    };

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

/// SUBtract BroadCast
pub fn iSubbc(vu: *Vu, instr: u32) void {
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
            const res = vu.getVfElement(f32, fs, e) - t;

            vu.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);
        const bcStr = getDestStr(@enumToInt(bc));

        const vd = vu.getVf(fd);

        std.debug.print("[VU{}       ] SUB{s}.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}\n", .{vu.vuNum, bcStr, destStr, fd, destStr, fs, destStr, ft, bcStr, fd, vd});
    }
}

/// WAIT Q
pub fn iWaitq(vu: *Vu) void {
    if (doDisasm) {
        std.debug.print("[VU{}       ] VWAITQ\n", .{vu.vuNum});
    }
}

/// Xfer GIF KICK
pub fn iXgkick(vu: *Vu, instr: u32) void {
    assert(vu.vuNum == 1);
    
    const is = getRs(instr);

    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});
        
        @panic("Index out of bounds");
    }

    vu.p1Addr = vu.getVi(@truncate(u4, is));

    vu.state = VuState.Xgkick;

    if (doDisasm) {
        std.debug.print("[VU{}       ] XGKICK VI[{}]; P1ADDR = 0x{X:0>3}\n", .{vu.vuNum, is, vu.getVi(@truncate(u4, is))});
    }
}

/// Xfer TOP
pub fn iXtop(vu: *Vu, instr: u32) void {
    assert(vu.vuNum == 1);

    const it = getRt(instr);

    if (it >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});
        
        @panic("Index out of bounds");
    }

    vu.setVi(@truncate(u4, it), vif1.vif1Top);

    if (doDisasm) {
        std.debug.print("[VU{}       ] XTOP VI[{}]; VI[{}] = 0x{X:0>4}\n", .{vu.vuNum, it, it, vif1.vif1Top});
    }
}
