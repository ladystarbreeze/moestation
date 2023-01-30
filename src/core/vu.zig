//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! vu.zig - Vector Unit module
//!

const std = @import("std");

const assert = std.debug.assert;

/// Macro mode control registers
const ControlReg = enum(u5) {
    Sf      = 16,
    Cf      = 18,
    R       = 20,
    I       = 21,
    Q       = 22,
    Cmsar0  = 27,
    Fbrst   = 28,
    VpuStat = 29,
};

/// Vector elements
pub const Element = enum(u4) {
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
        return (@as(u128, self.w) << 96) | (@as(u128, self.z) << 64) | (@as(u128, self.y) << 32) | @as(u128, self.x);
    }

    /// Returns an element
    pub fn getElement(self: Vf, e: Element) f32 {
        var data: u32 = undefined;

        switch (e) {
            Element.W => data = self.w,
            Element.Z => data = self.z,
            Element.Y => data = self.y,
            Element.X => data = self.x,
        }

        return @bitCast(f32, data);
    }

    /// Sets the full 128-bit VF
    pub fn set(self: *Vf, data: u128) void {
        self.x = @truncate(u32, data);
        self.y = @truncate(u32, data >> 32);
        self.z = @truncate(u32, data >> 64);
        self.w = @truncate(u32, data >> 96);
    }

    /// Sets an element
    pub fn setElement(self: *Vf, e: Element, data: f32) void {
        const data_ = @bitCast(u32, data);

        switch (e) {
            Element.W => self.w = data_,
            Element.Z => self.z = data_,
            Element.Y => self.y = data_,
            Element.X => self.x = data_,
        }
    }
};

/// Vector Unit
pub const Vu = struct {
     vuNum: u1,              // VU number
     other: *Vu = undefined, // Other VU

    // VU memory
     vuMem: []u8 = undefined,
    vuCode: []u8 = undefined,

    // VU registers
        vf: [32]Vf  = undefined,
        vi: [16]u16 = undefined,
       acc: Vf      = undefined,
         q: f32     = 0.0,
     cmsar: u16     = 0,

    /// Reset
    pub fn reset(self: *Vu) void {
        std.debug.print("[VU{}       ] Reset!\n", .{self.vuNum});
    }
    
    /// Force break
    pub fn forceBreak(self: *Vu) void {
        std.debug.print("[VU{}       ] Force break!\n", .{self.vuNum});
    }

    /// Returns an integer register (macro mode)
    pub fn get(self: Vu, comptime T: type, idx: u5) T {
        assert(self.vuNum == 0);

        assert(T == u32 or T == u128);

        if (T == u32) {
            @panic("Unhandled COP2 read");
        }

        return self.getVf(idx);
    }

    /// Returns a macro mode control register
    pub fn getControl(self: Vu, comptime T: type, idx: u5) T {
        assert(self.vuNum == 0);

        var data: T = undefined;

        switch (idx) {
            0 ... 15 => {
                //info("   [VU0 (COP2)] Control register read ({s}) @ $VI{}.", .{@typeName(T), idx});

                data = @as(T, self.getVi(@truncate(u4, idx)));
            },
            @enumToInt(ControlReg.Cf) => {
                std.debug.print("[COP2      ] Control register read ({s}) @ $CF\n", .{@typeName(T)});

                data = 0;
            },
            @enumToInt(ControlReg.Fbrst) => {
                std.debug.print("[COP2      ] Control register read ({s}) @ $FBRST\n", .{@typeName(T)});

                data = 0;
            },
            @enumToInt(ControlReg.VpuStat) => {
                std.debug.print("[COP2      ] Control register read ({s}) @ $VPU_STAT\n", .{@typeName(T)});

                data = 0;
            },
            else => {
                std.debug.print("[COP2      ] Unhandled control register read ({s}) @ ${}\n", .{@typeName(T), idx});

                @panic("Unhandled COP2 read");
            }
        }

        return data;
    }

     /// Returns a VI register
    pub fn getVi(self: Vu, idx: u4) u16 {
        return self.vi[idx];
    }

    /// Returns a VF register
    pub fn getVf(self: Vu, idx: u5) u128 {
        return self.vf[idx].get();
    }

    /// Returns a VF element
    pub fn getVfElement(self: Vu, comptime T: type, idx: u5, e: Element) T {
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

    /// Sets an integer register (macro mode)
    pub fn set(self: *Vu, comptime T: type, idx: u5, data: T) void {
        assert(self.vuNum == 0);

        assert(T == u32 or T == u128);

        if (T == u32) {
            @panic("Unhandled COP2 write");
        }

        self.setVf(idx, data);
    }

    /// Sets a macro mode control register
    pub fn setControl(self: *Vu, comptime T: type, idx: u5, data: T) void {
        assert(self.vuNum == 0);

        switch (idx) {
            0 ... 15 => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $VI[{}] = 0x{X:0>8}\n", .{@typeName(T), idx, data});

                self.setVi(@truncate(u4, idx), @truncate(u16, data));
            },
            @enumToInt(ControlReg.Sf) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $SF = 0x{X:0>8}\n", .{@typeName(T), data});
            },
            @enumToInt(ControlReg.Cf) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $CF = 0x{X:0>8}\n", .{@typeName(T), data});
            },
            @enumToInt(ControlReg.R) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $R = 0x{X:0>8}\n", .{@typeName(T), data});
            },
            @enumToInt(ControlReg.I) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $I = 0x{X:0>8}\n", .{@typeName(T), data});
            },
            @enumToInt(ControlReg.Q) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $Q = 0x{X:0>8}\n", .{@typeName(T), data});

                self.q = @bitCast(f32, @truncate(u32, data));
            },
            @enumToInt(ControlReg.Cmsar0) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $CMSAR0 = 0x{X:0>8}\n", .{@typeName(T), data});

                self.cmsar = @truncate(u16, data);
            },
            @enumToInt(ControlReg.Fbrst) => {
                std.debug.print("[COP2      ] Control register write ({s}) @ $FBRST = 0x{X:0>8}\n", .{@typeName(T), data});

                if ((data & 1) != 0) {
                    self.forceBreak();
                }
                if ((data & (1 << 1)) != 0) {
                    self.reset();
                }
                if ((data & (1 << 8)) != 0) {
                    self.other.forceBreak();
                }
                if ((data & (1 << 9)) != 0) {
                    self.other.reset();
                }
            },
            else => {
                std.debug.print("[COP2      ] Unhandled control register write ({s}) @ ${} = 0x{X:0>8}\n", .{@typeName(T), idx, data});

                @panic("Unhandled COP2 write");
            }
        }
    }

    /// Sets `other` pointer
    pub fn setOther(self: *Vu, other: *Vu) void {
        self.other = other;
    }

    /// Sets a VI register
    pub fn setVi(self: *Vu, idx: u4, data: u16) void {
        self.vi[idx] = data;

        self.vi[0] = 0;
    }

    /// Sets a VF register
    pub fn setVf(self: *Vu, idx: u5, data: u128) void {
        self.vf[idx].set(data);

        self.vf[0].set(0x3F800000 << 96);
    }

    /// Sets a VF element
    pub fn setVfElement(self: *Vu, comptime T: type, idx: u5, e: Element, data: T) void {
        assert(T == u32 or T == f32);

        const data_ = if (T == f32) @bitCast(u32, data) else data;

        switch (e) {
            Element.W => self.vf[idx].w = data_,
            Element.Z => self.vf[idx].z = data_,
            Element.Y => self.vf[idx].y = data_,
            Element.X => self.vf[idx].x = data_,
        }

        self.vf[0].set(0x3F800000 << 96);
    }

    /// Writes data from VU data memory
    pub fn writeData(self: *Vu, comptime T: type, addr: u12, data: T) void {
        if (self.vuNum == 0 and (addr + @sizeOf(T)) >= 0x1000) {
            std.debug.print("[VU{}       ] Out-of-bounds write ({s}) @ 0x{X:0>4}/n", .{self.vuNum, @typeName(T), addr});

            @panic("Write out of bounds");
        }

        @memcpy(@ptrCast([*]u8, &self.vuMem[addr]), @ptrCast([*]const u8, &data), @sizeOf(T));
    }
};
