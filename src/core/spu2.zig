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

const dmac = @import("dmac_iop.zig");

const Channel = dmac.Channel;

/// SPU2 registers
const Spu2Reg = enum(u32) {
    PmOn       = 0x1F90_0180,
    NoiseOn    = 0x1F90_0184,
    Vmixl      = 0x1F90_0188,
    Vmixel     = 0x1F90_018C,
    Vmixr      = 0x1F90_0190,
    Vmixer     = 0x1F90_0194,
    Mmix       = 0x1F90_0198,
    CoreAttr   = 0x1F90_019A,
    IrqAddr    = 0x1F90_019C,
    KeyOn      = 0x1F90_01A0,
    KeyOff     = 0x1F90_01A4,
    SpuAddr    = 0x1F90_01A8,
    SpuData    = 0x1F90_01AC,
    AdmaStat   = 0x1F90_01B0,
    Esa        = 0x1F90_02E0,
    Eea        = 0x1F90_033C,
    Endx       = 0x1F90_0340,
    CoreStat   = 0x1F90_0344,
    Mvoll      = 0x1F90_0760,
    Mvolr      = 0x1F90_0762,
    Evoll      = 0x1F90_0764,
    Evolr      = 0x1F90_0766,
    Avoll      = 0x1F90_0768,
    Avolr      = 0x1F90_076A,
    Bvoll      = 0x1F90_076C,
    Bvolr      = 0x1F90_076E,
    SpdifOut   = 0x1F90_07C0,
    IrqInfo    = 0x1F90_07C2,
    SpdifMode  = 0x1F90_07C6,
    SpdifMedia = 0x1F90_07C8,
    RevViir    = 0x1F90_0774,
    RevVcomb1  = 0x1F90_0776,
    RevVcomb2  = 0x1F90_0778,
    RevVcomb3  = 0x1F90_077A,
    RevVcomb4  = 0x1F90_077C,
    RevVwall   = 0x1F90_077E,
    RevApf1    = 0x1F90_0780,
    RevApf2    = 0x1F90_0782,
    RevVlin    = 0x1F90_0784,
    RevVrin    = 0x1F90_0786,
};

/// TODO: properly implement all registers eventually.

/// VMIXL/R
var vmixl = [2]u16 {0, 0};
var vmixr = [2]u16 {0, 0};

/// VMIXEL/R
var vmixel = [2]u16 {0, 0};
var vmixer = [2]u16 {0, 0};

/// SPU_ADDR
var     spuAddr: u24 = 0;
var currSpuAddr: u24 = 0;

/// ADMA_STAT
var admaStat: u16 = 0;

/// CORE_ATTR
var coreAttr = [2]u16 {0, 0};

/// CORE_STAT
const coreStatDmaReady: u16 = 1 << 7;
const  coreStatDmaBusy: u16 = 1 << 10;

var coreStat: u16 = 0;

/// Reads data from an SPU2 register
pub fn read(addr: u32) u16 {
    var data: u16 = undefined;

    if (addr >= 0x1F90_0760 and addr < 0x1F90_07B0) {
        const coreId = @bitCast(u1, addr >= 0x1F90_0788);

        switch (addr - (0x28 * @as(u32, coreId))) {
            else => {
                warn("[SPU2      ] Unhandled read @ 0x{X:0>8} (Core {}).", .{addr, coreId});

                data = 0;
            }
        }
    } else if (addr >= 0x1F90_07B0) {
        // SPU2 control registers
        switch (addr) {
            else => {
                warn("[SPU2      ] Unhandled read @ 0x{X:0>8}.", .{addr});

                data = 0;
            }
        }
    } else {
        const coreId = @bitCast(u1, addr >= 0x1F90_0400);

        const addr_ = addr - 0x400 * @as(u32, coreId);

        if ((addr_ >= 0x1F90_0180 and addr_ < 0x1F90_01C0) or addr_ >= 0x1F90_02E0) {
            switch (addr_) {
                @enumToInt(Spu2Reg.Vmixl) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXL_H).", .{addr});

                    data = vmixl[1];
                },
                @enumToInt(Spu2Reg.Vmixl) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXL_L).", .{addr});

                    data = vmixl[0];
                },
                @enumToInt(Spu2Reg.Vmixel) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXEL_H).", .{addr});

                    data = vmixel[1];
                },
                @enumToInt(Spu2Reg.Vmixel) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXEL_L).", .{addr});

                    data = vmixel[0];
                },
                @enumToInt(Spu2Reg.Vmixr) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXR_H).", .{addr});

                    data = vmixr[1];
                },
                @enumToInt(Spu2Reg.Vmixr) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXR_L).", .{addr});

                    data = vmixr[0];
                },
                @enumToInt(Spu2Reg.Vmixer) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXER_H).", .{addr});

                    data = vmixer[1];
                },
                @enumToInt(Spu2Reg.Vmixer) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (VMIXER_L).", .{addr});

                    data = vmixer[0];
                },
                @enumToInt(Spu2Reg.KeyOn) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (KEY_ON_L{}).", .{addr, coreId});

                    data = 0;
                },
                @enumToInt(Spu2Reg.KeyOn) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (KEY_ON_H{}).", .{addr, coreId});

                    data = 0;
                },
                @enumToInt(Spu2Reg.KeyOff) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (KEY_OFF_L{}).", .{addr, coreId});

                    data = 0;
                },
                @enumToInt(Spu2Reg.KeyOff) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (KEY_OFF_H{}).", .{addr, coreId});

                    data = 0;
                },@enumToInt(Spu2Reg.SpuAddr) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (SPU_ADDR_H).", .{addr});

                    data = @truncate(u16, spuAddr >> 16);
                },
                @enumToInt(Spu2Reg.SpuAddr) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (SPU_ADDR_L).", .{addr});

                    data = @truncate(u16, spuAddr);
                },
                @enumToInt(Spu2Reg.SpuData) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (SPU_DATA).", .{addr});

                    assert(false);
                },
                @enumToInt(Spu2Reg.AdmaStat) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (ADMA_STAT).", .{addr});

                    data = admaStat;
                },
                @enumToInt(Spu2Reg.CoreAttr) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (CORE_ATTR{}).", .{addr, coreId});

                    data = coreAttr[coreId];
                },
                @enumToInt(Spu2Reg.Eea) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (EEA{}).", .{addr, coreId});

                    data = 0;
                },
                @enumToInt(Spu2Reg.Endx) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (ENDX_H{}).", .{addr, coreId});

                    data = 0;
                },
                @enumToInt(Spu2Reg.Endx) + 2 => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (ENDX_L{}).", .{addr, coreId});

                    data = 0;
                },
                @enumToInt(Spu2Reg.CoreStat) => {
                    info("   [SPU2      ] Read @ 0x{X:0>8} (CORE_STAT).", .{addr});

                    data = coreStat;
                },
                else => {
                    warn("[SPU2      ] Unhandled read @ 0x{X:0>8} (Core {}).", .{addr, coreId});

                    data = 0;
                }
            }
        } else {
            warn("[SPU2      ] Read @ 0x{X:0>8} (Core {} Voice).", .{addr, coreId});

            data = 0;
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
            @enumToInt(Spu2Reg.Evoll) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (EVOLL{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.Evolr) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (EVOLR{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.Avoll) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (AVOLL{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.Avolr) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (AVOLR{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.Bvoll) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (BVOLL{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.Bvolr) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (BVOLR{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevViir) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VIIR{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVcomb1) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VCOMB1_{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVcomb2) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VCOMB2_{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVcomb3) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VCOMB3_{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVcomb4) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VCOMB4_{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVwall) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VWALL{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevApf1) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_APF1_{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevApf2) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_APF2_{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVlin) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VLIN{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            @enumToInt(Spu2Reg.RevVrin) => {
                info("   [SPU2      ] Write @ 0x{X:0>8} (REV_VRIN{}) = 0x{X:0>4}.", .{addr, coreId, data});
            },
            else => {
                warn("[SPU2      ] Unhandled write @ 0x{X:0>8} (Core {}) = 0x{X:0>4}.", .{addr, coreId, data});

                //assert(false);
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
                warn("[SPU2      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>4}.", .{addr, data});

                //assert(false);
            }
        }
    } else {
        const coreId = @bitCast(u1, addr >= 0x1F90_0400);

        const addr_ = addr - 0x400 * @as(u32, coreId);

        if ((addr_ >= 0x1F90_0180 and addr_ < 0x1F90_01C0) or addr_ >= 0x1F90_02E0) {
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
                @enumToInt(Spu2Reg.Vmixl) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXL_H) = 0x{X:0>4}.", .{addr, data});

                    vmixl[1] = data;
                },
                @enumToInt(Spu2Reg.Vmixl) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXL_L) = 0x{X:0>4}.", .{addr, data});

                    vmixl[0] = data;
                },
                @enumToInt(Spu2Reg.Vmixel) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXEL_H) = 0x{X:0>4}.", .{addr, data});

                    vmixel[1] = data;
                },
                @enumToInt(Spu2Reg.Vmixel) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXEL_L) = 0x{X:0>4}.", .{addr, data});

                    vmixel[0] = data;
                },
                @enumToInt(Spu2Reg.Vmixr) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXR_H) = 0x{X:0>4}.", .{addr, data});

                    vmixr[1] = data;
                },
                @enumToInt(Spu2Reg.Vmixr) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXR_L) = 0x{X:0>4}.", .{addr, data});

                    vmixr[0] = data;
                },
                @enumToInt(Spu2Reg.Vmixer) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXER_H) = 0x{X:0>4}.", .{addr, data});

                    vmixer[1] = data;
                },
                @enumToInt(Spu2Reg.Vmixer) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (VMIXER_L) = 0x{X:0>4}.", .{addr, data});

                    vmixer[0] = data;
                },
                @enumToInt(Spu2Reg.Mmix) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (MMIX{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.KeyOn) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (KEY_ON_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.KeyOn) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (KEY_ON_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.KeyOff) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (KEY_OFF_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.KeyOff) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (KEY_OFF_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.SpuAddr) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (SPU_ADDR_H) = 0x{X:0>4}.", .{addr, data});

                    spuAddr &= 0xFFFF;
                    spuAddr |= @as(u24, data) << 16;

                    currSpuAddr = spuAddr;
                },
                @enumToInt(Spu2Reg.SpuAddr) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (SPU_ADDR_L) = 0x{X:0>4}.", .{addr, data});

                    spuAddr &= ~@as(u24, 0xFFFF);
                    spuAddr |= @as(u24, data);

                    currSpuAddr = spuAddr;
                },
                @enumToInt(Spu2Reg.SpuData) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (SPU_DATA{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.CoreAttr) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (CORE_ATTR{}) = 0x{X:0>4}.", .{addr, coreId, data});

                    if ((admaStat & 3) == 0) {
                        const req = (data & (3 << 4)) != 0;

                        setDmaRequest(coreId, req);
                    }

                    if ((data & (1 << 15)) != 0) {
                        // Clear DMA Busy flag, set DMA Ready flag
                        coreStat &= ~(coreStatDmaBusy | coreStatDmaReady);
                    }

                    coreAttr[coreId] = data & 0x7FFF;
                },
                @enumToInt(Spu2Reg.IrqAddr) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (IRQ_ADDR_H{}) = 0x{X:0>4}.", .{addr, coreId, data});

                    assert(false);
                },
                @enumToInt(Spu2Reg.IrqAddr) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (IRQ_ADDR_L{}) = 0x{X:0>4}.", .{addr, coreId, data});

                    assert(false);
                },
                @enumToInt(Spu2Reg.AdmaStat) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ADMA_STAT) = 0x{X:0>4}.", .{addr, data});

                    admaStat = data;

                    if ((data & 1) != 0) {
                        setDmaRequest(0, true);
                    } else {
                        setDmaRequest(0, false);
                    }

                    if ((data & 2) != 0) {
                        setDmaRequest(1, true);
                    } else {
                        setDmaRequest(1, false);
                    }
                },
                // Why is ESA backwards??
                @enumToInt(Spu2Reg.Esa) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ESA_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.Esa) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ESA_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                0x1F90_02E4 ... 0x1F90_02FF => {
                    warn("[SPU2      ] Write @ 0x{X:0>8} (Core {} Unknown) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.Eea) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (EEA{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.Endx) => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ENDX_L{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                @enumToInt(Spu2Reg.Endx) + 2 => {
                    info("   [SPU2      ] Write @ 0x{X:0>8} (ENDX_H{}) = 0x{X:0>4}.", .{addr, coreId, data});
                },
                else => {
                    warn("[SPU2      ] Unhandled write @ 0x{X:0>8} (Core {}) = 0x{X:0>4}.", .{addr, coreId, data});

                    //assert(false);
                }
            }
        } else {
            warn("[SPU2      ] Write @ 0x{X:0>8} (Core {} Voice) = 0x{X:0>4}.", .{addr, coreId, data});
        }
    }
}

/// SPU DMA writes
pub fn writeDmac(coreId: u1, data: u32) void {
    info("   [SPU2      ] Write @ 0x{X:0>8} (Core {}) = 0x{X:0>8}.", .{currSpuAddr, coreId, data});

    currSpuAddr += 4;

    coreStat |= coreStatDmaBusy;
}

/// Sets SPU DMA requests
fn setDmaRequest(coreId: u1, req: bool) void {
    info("   [SPU2      ] Core {} DMA request = {}.", .{coreId, req});

    if (coreId == 0) {
        dmac.setRequest(Channel.Spu1, req);
    } else {
        dmac.setRequest(Channel.Spu2, req);
    }

    if (req) {
        coreStat &= ~(coreStatDmaReady);
    } else {
        coreStat &= ~(coreStatDmaBusy);
        coreStat |= coreStatDmaReady;
    }
}

/// Completes an SPU DMA transfer
pub fn dmaEnd(coreId: u1) void {
    info("   [SPU2      ] Core {} DMA transfer end.", .{coreId});

    coreStat &= ~(coreStatDmaBusy);
    coreStat |= coreStatDmaReady;

    if (coreId == 0 and (admaStat & 1) != 0) {
        setDmaRequest(0, true);
    }

    if (coreId == 1 and (admaStat & 2) != 0) {
        setDmaRequest(1, true);
    }
}
