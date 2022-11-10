//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! core/spu2.zig - Sound Processing Unit2 module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

/// SPU2 registers
const Spu2Reg = enum(u32) {
    PmOn       = 0x1F90_0180,
    NoiseOn    = 0x1F90_0184,
    CoreAttr   = 0x1F90_019A,
    KeyOff     = 0x1F90_01A4,
    AdmaStat   = 0x1F90_01B0,
    Esa        = 0x1F90_02E0,
    CoreStat   = 0x1F90_0344,
    Mvoll      = 0x1F90_0760,
    Mvolr      = 0x1F90_0762,
    SpdifOut   = 0x1F90_07C0,
    IrqInfo    = 0x1F90_07C2,
    SpdifMode  = 0x1F90_07C6,
    SpdifMedia = 0x1F90_07C8,
};

/// Reads data from an SPU2 register
pub fn read(addr: u32) u16 {
    var data: u16 = undefined;

    if (addr >= 0x1F90_0760 and addr < 0x1F90_07B0) {
        const coreId = @bitCast(u1, addr >= 0x1F90_0788);

        switch (addr - (0x28 * @as(u32, coreId))) {
            else => {
                err("  [SPU2      ] Unhandled read @ 0x{X:0>8} (Core {}).", .{addr, coreId});

                assert(false);
            }
        }
    } else if (addr >= 0x1F90_07B0) {
        // SPU2 control registers
        switch (addr) {
            else => {
                err("  [SPU2      ] Unhandled read @ 0x{X:0>8}.", .{addr});

                assert(false);
            }
        }
    } else {
        const coreId = @bitCast(u1, addr >= 0x1F90_0400);

        const addr_ = addr - 0x400 * @as(u32, coreId);

        if ((addr_ >= 0x1F90_0180 and addr_ < 0x1F90_01C0) or addr_ >= 0x1F90_02F0) {
            switch (addr_) {
                @enumToInt(Spu2Reg.CoreStat) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (CORE_STAT{}).", .{addr, coreId});

                    data = 0;
                },
                else => {
                    err("  [SPU2      ] Unhandled read @ 0x{X:0>8} (Core {}).", .{addr, coreId});

                    assert(false);
                }
            }
        } else {
            err("  [SPU2      ] Unhandled read @ 0x{X:0>8} (Core {}).", .{addr, coreId});

            assert(false);
        }
    }

    return data;
}

/// Writes data to an SPU2 register
pub fn write(addr: u32, data: u16) void {
    if (addr >= 0x1F90_0760 and addr < 0x1F90_07B0) {
        const coreId = @bitCast(u1, addr >= 0x1F90_0788);

        switch (addr - (0x28 * @as(u32, coreId))) {
            @enumToInt(Spu2Reg.Mvoll) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (MVOLL{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.Mvolr) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (MVOLR{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            else => {
                err("  [SPU2      ] Unhandled write @ 0x{X:0>8} (Core {}) = 0x{X:0>4}.", .{addr, coreId, data});

                assert(false);
            }
        }
    } else if (addr >= 0x1F90_07B0) {
        // SPU2 control registers
        switch (addr) {
            @enumToInt(Spu2Reg.SpdifOut) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (SPDIF_OUT) = 0x{X:0>4}.", .{addr, data});
            },
            @enumToInt(Spu2Reg.IrqInfo) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (IRQ_INFO) = 0x{X:0>4}.", .{addr, data});
            },
            @enumToInt(Spu2Reg.SpdifMode) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (SPDIF_MODE) = 0x{X:0>4}.", .{addr, data});
            },
            @enumToInt(Spu2Reg.SpdifMedia) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (SPDIF_MEDIA) = 0x{X:0>4}.", .{addr, data});
            },
            0x1F90_07CA => {
                warn("[SPU2      ] Write @ 0x{X:0>8} (Unknown) = 0x{X:0>4}.", .{addr, data});
            },
            else => {
                err("  [SPU2      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>4}.", .{addr, data});

                assert(false);
            }
        }
    } else {
        const coreId = @bitCast(u1, addr >= 0x1F90_0400);

        const addr_ = addr - 0x400 * @as(u32, coreId);

        if ((addr_ >= 0x1F90_0180 and addr_ < 0x1F90_01C0) or addr_ >= 0x1F90_02F0) {
            switch (addr_) {
                @enumToInt(Spu2Reg.PmOn) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (PM_ON_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.PmOn) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (PM_ON_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.NoiseOn) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (NOISE_ON_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.NoiseOn) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (NOISE_ON_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.KeyOff) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (KEY_OFF_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.KeyOff) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (KEY_OFF_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.CoreAttr) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (CORE_ATTR{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.AdmaStat) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ADMA_STAT{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                // Why is ESA backwards??
                @enumToInt(Spu2Reg.Esa) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ESA_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.Esa) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ESA_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                else => {
                    err("  [SPU2      ] Unhandled write @ 0x{X:0>8} (Core {}) = 0x{X:0>4}.", .{addr, coreId, data});

                    assert(false);
                }
            }
        } else {
            err("  [SPU2      ] Unhandled write @ 0x{X:0>8} (Core {}) = 0x{X:0>4}.", .{addr, coreId, data});

            assert(false);
        }
    }
}
