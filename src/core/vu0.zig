//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! vu0.zig - Vector Unit 0 module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

/// Macro mode control registers
const ControlReg = enum(u5) {
    Fbrst = 28,
};

/// Vector elements
const Element = enum(u4) {
    W = 1 << 0,
    Z = 1 << 1,
    Y = 1 << 2,
    X = 1 << 3,
};

/// VU0 floating-point register
const Vf = struct {
    x: u32,
    y: u32,
    z: u32,
    w: u32,

    /// Returns the full 128-bit VF
    pub fn get(self: Vf) u128 {
        return (@as(u128, self.x) << 96) | (@as(u128, self.y) << 64) | (@as(u128, self.z) << 32) | @as(u128, self.w);
    }

    /// Sets the full 128-bit VF
    pub fn set(self: *Vf, data: u128) void {
        self.x = @truncate(u32, data >> 96);
        self.y = @truncate(u32, data >> 64);
        self.z = @truncate(u32, data >> 32);
        self.w = @truncate(u32, data);
    }
};

/// VU0 register file
const RegFile = struct {
    vf: [32]Vf  = undefined,
    vi: [16]u16 = undefined,

    /// Returns a VI register
    pub fn getVi(self: RegFile, idx: u4) u16 {
        return self.vi[idx];
    }

    /// Returns a VF register
    pub fn getVf(self: RegFile, idx: u5) u128 {
        return self.vf[idx].get();
    }

    /// Returns a VF element
    pub fn getVfElement(self: RegFile, comptime T: type, idx: u5, e: Element) T {
        assert(T == u32 or T == f32);

        var data: u32 = 0;

        switch (e) {
            Element.W => data = self.vf[idx].w,
            Element.Z => data = self.vf[idx].z,
            Element.Y => data = self.vf[idx].y,
            Element.X => data = self.vf[idx].x,
        }

        if (T == f32) {
            return @bitCast(f32, data);
        }

        return data;
    }

    /// Sets a VI register
    pub fn setVi(self: *RegFile, idx: u4, data: u16) void {
        self.vi[idx] = data;

        self.vi[0] = 0;
    }

    /// Sets a VF register
    pub fn setVf(self: *RegFile, idx: u5, data: u128) void {
        self.vf[idx].set(data);

        self.vf[0].set(0x3F800000);
    }

    /// Sets a VF element
    pub fn setVfElement(self: *RegFile, comptime T: type, idx: u5, e: Element, data: T) void {
        assert(T == u32 or T == f32);

        const data_ = if (T == f32) @bitCast(u32, data) else data;

        switch (e) {
            Element.W => self.vf[idx].w = data_,
            Element.Z => self.vf[idx].z = data_,
            Element.Y => self.vf[idx].y = data_,
            Element.X => self.vf[idx].x = data_,
        }

        self.vf[0].set(0);
    }
};

const doDisasm = true;

/// VU0 mem
pub var vuMem: []u8 = undefined;

var regFile: RegFile = RegFile{};

/// Returns a COP2 register
pub fn get(comptime T: type, idx: u5) T {
    assert(T == u32 or T == u128);

    if (T == u32) {
        @panic("Unhandled COP2 read");
    }

    return regFile.getVf(idx);
}

/// Returns a COP2 control register
pub fn getControl(comptime T: type, idx: u5) T {
    var data: T = undefined;

    switch (idx) {
        0 ... 15 => {
            //info("   [VU0 (COP2)] Control register read ({s}) @ $VI{}.", .{@typeName(T), idx});

            data = @as(T, regFile.getVi(@truncate(u4, idx)));
        },
        @enumToInt(ControlReg.Fbrst) => {
            info("   [VU0 (COP2)] Control register read ({s}) @ $FBRST.", .{@typeName(T)});

            data = 0;
        },
        else => {
            err("  [VU0 (COP2)] Unhandled control register read ({s}) @ ${}.", .{@typeName(T), idx});

            assert(false);
        }
    }

    return data;
}

/// Writes VU data memory
fn write(comptime T: type, addr: u12, data: T) void {
    assert((addr + @sizeOf(T)) < 0x1000);

    @memcpy(@ptrCast([*]u8, &vuMem[addr]), @ptrCast([*]const u8, &data), @sizeOf(T));
}

/// Sets a COP2 register
pub fn set(comptime T: type, idx: u5, data: T) void {
    assert(T == u32 or T == u128);

    if (T == u32) {
        @panic("Unhandled COP2 write");
    }

    regFile.setVf(idx, data);
}

/// Sets a COP2 control register
pub fn setControl(comptime T: type, idx: u5, data: T) void {
    switch (idx) {
        0 ... 15 => {
            //info("   [VU0 (COP2)] Control register write ({s}) @ $VI{} = 0x{X:0>8}.", .{@typeName(T), idx, data});

            regFile.setVi(@truncate(u4, idx), @truncate(u16, data));
        },
        @enumToInt(ControlReg.Fbrst) => {
            info("   [VU0 (COP2)] Control register write ({s}) @ $FBRST = 0x{X:0>8}.", .{@typeName(T), data});

            if ((data & 1) != 0) {
                info("   [VU0 (COP2)] VU0 force break.", .{});
            }
            if ((data & (1 << 1)) != 0) {
                info("   [VU0 (COP2)] VU0 reset.", .{});
            }
            if ((data & (1 << 8)) != 0) {
                info("   [VU0 (COP2)] VU1 force break.", .{});
            }
            if ((data & (1 << 9)) != 0) {
                info("   [VU0 (COP2)] VU1 reset.", .{});
            }
        },
        else => {
            err("  [VU0 (COP2)] Unhandled control register write ({s}) @ ${} = 0x{X:0>8}.", .{@typeName(T), idx, data});

            assert(false);
        }
    }
}

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

/// Integer Store
pub fn iIswr(instr: u32) void {
    const dest = getDest(instr);

    const it = getRt(instr);
    const is = getRs(instr);

    assert(it < 16 and is < 16);

    const addr = @truncate(u12, regFile.getVi(@truncate(u4, is)) << 4);
    const data = regFile.getVi(@truncate(u4, it));

    var i: u12 = 0;
    while (i < 4) : (i += 1) {
        if ((dest & (@as(u4, 1) << (3 - @truncate(u2, i)))) != 0) {
            write(u32, addr +% (i * 4), @as(u32, data));
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        info("   [VU0       ] ISWR.{s} VI[{}]{s}, (VI[{}])", .{destStr, it, destStr, is});
    }
}

/// Store Quadword with post-Increment
pub fn iSqi(instr: u32) void {
    const dest = getDest(instr);

    const ft = getRt(instr);
    const is = getRs(instr);
    
    assert(is < 16);

    const addr = @truncate(u12, regFile.getVi(@truncate(u4, is)) << 4);

    var i: u12 = 0;
    while (i < 4) : (i += 1) {
        if ((dest & (@as(u4, 1) << (3 - @truncate(u2, i)))) != 0) {
            const e = @intToEnum(Element, @as(u4, 1) << (3 - @truncate(u2, i)));

            write(u32, addr +% (i * 4), regFile.getVfElement(u32, ft, e));
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        info("   [VU0       ] SQI.{s} VF[{}]{s}, (VI[{}]++)", .{destStr, ft, destStr, is});
    }
}

/// floating-point SUBtract
pub fn iSub(instr: u32) void {
    const dest = getDest(instr);

    const fd = getRd(instr);
    const ft = getRt(instr);
    const fs = getRs(instr);

    var i: u4 = 1;
    while (i != 0) : (i <<= 1) {
        if ((dest & i) != 0) {
            const e = @intToEnum(Element, i);
            const res = regFile.getVfElement(f32, fs, e) - regFile.getVfElement(f32, ft, e);

            regFile.setVfElement(f32, fd, e, res);
        }
    }

    if (doDisasm) {
        const destStr = getDestStr(dest);

        const vd = regFile.getVf(fd);

        info("   [VU0       ] SUB.{s} VF[{}]{s}, VF[{}]{s}, VF[{}]{s}; VF[{}] = 0x{X:0>32}", .{destStr, fd, destStr, fs, destStr, ft, destStr, fd, vd});
    }
}
