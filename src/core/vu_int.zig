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
    Ibne    = 0x29,
    Special = 0x40,
};

const LowerOpSpecial = enum(u6) {
    Iadd = 0x30,
};

const LowerOpSpecial2 = enum(u7) {
    Xtop   = 0x28,
    Xgkick = 0x2C,
    Move   = 0x30,
    Sqi    = 0x35,
    Div    = 0x38,
};

const UpperOp = enum(u7) {
    Maddbc = 0x08,
    Mulq   = 0x1C,
    Madd   = 0x29,
};

const UpperOpSpecial = enum(u7) {
    Maddabc = 0x08,
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
        @enumToInt(LowerOp.Ibne   ) => iIbne(vu, instr),
        @enumToInt(LowerOp.Special) => {
            const funct = @truncate(u6, instr);

            if ((funct >> 2) == 0xF) {
                const funct2 = (@truncate(u6, instr >> 6) << 2) | (funct & 3);

                switch (funct2) {
                    @enumToInt(LowerOpSpecial2.Xtop  ) => iXtop(vu, instr),
                    @enumToInt(LowerOpSpecial2.Xgkick) => iXgkick(vu, instr),
                    @enumToInt(LowerOpSpecial2.Move  ) => iMove(vu, instr),
                    @enumToInt(LowerOpSpecial2.Sqi   ) => iSqi(vu, instr),
                    @enumToInt(LowerOpSpecial2.Div   ) => iDiv(vu, instr),
                    else => {
                        std.debug.print("[VU{}       ] Unhandled 11-bit lower instruction 0x{X:0>2} (0x{X:0>8})\n", .{vu.vuNum, funct2, instr});

                        @panic("Unhandled lower instruction");
                    }
                }
            } else {
                switch (funct) {
                    @enumToInt(LowerOpSpecial.Iadd) => iIadd(vu, instr),
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
            @enumToInt(UpperOp.Maddbc) ... @enumToInt(UpperOp.Maddbc) + 3 => iMaddbc(vu, instr),
            @enumToInt(UpperOp.Mulq  ) => iMulq(vu, instr),
            @enumToInt(UpperOp.Madd  ) => iMadd(vu, instr),
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

    if (vu.getVfElement(f32, ft, ftf) == 0.0) {
        std.debug.print("[VU{}       ] DIV by 0\n", .{vu.vuNum});

        @panic("DIV by 0");
    }

    vu.q = vu.getVfElement(f32, fs, fsf) / vu.getVfElement(f32, ft, ftf);

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

/// Float to 28:4 fixed-point integer
pub fn iFtoi4(vu: *Vu, instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const fs = getRs(instr);

    if (dest & (1 << 0) != 0) {
        vu.setVfElement(u32, ft, Element.W, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.W)) * 16.0)))));
    }
    if (dest & (1 << 1) != 0) {
        vu.setVfElement(u32, ft, Element.Z, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.Z)) * 16.0)))));
    }
    if (dest & (1 << 2) != 0) {
        vu.setVfElement(u32, ft, Element.Y, @truncate(u32, @bitCast(u64, @floatToInt(i64, @round(@as(f64, vu.getVfElement(f32, fs, Element.Y)) * 16.0)))));
    }
    if (dest & (1 << 3) != 0) {
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

        std.debug.print("[VU{}       ] SQ.{s} VF[{}]{s}, {}(VI[{}])\n", .{vu.vuNum, destStr, fs, destStr, @bitCast(i16, imm), it});
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

        std.debug.print("[VU{}       ] SQI.{s} VF[{}]{s}, (VI[{}]++)\n", .{vu.vuNum, destStr, fs, destStr, it});
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

/// WAIT Q
pub fn iWaitq(vu: *Vu) void {
    if (doDisasm) {
        std.debug.print("[VU{}       ] VWAITQ\n", .{vu.vuNum});
    }
}

/// Xfer GIF KICK
pub fn iXgkick(vu: *Vu, instr: u32) void {
    assert(vu.vuNum == 1);

    if (gif.getActivePath() == ActivePath.Path1) {
        std.debug.print("[VU1       ] PATH1 still running\n", .{});

        @panic("PATH1 still running");
    }

    const is = getRs(instr);

    if (is >= 16) {
        std.debug.print("[VU{}       ] Index out of bounds\n", .{vu.vuNum});
        
        @panic("Index out of bounds");
    }

    gif.setPath1Addr(vu.getVi(@truncate(u4, is)));

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
