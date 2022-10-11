//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! dmac.zig - DMA controller module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

/// DMA channels
const Channel = enum(u4) {
    Vif0,
    Vif1,
    Path3,
    IpuFrom,
    IpuTo,
    Sif0,
    Sif1,
    Sif2,
    SprFrom,
    SprTo,
};

/// DMA channel registers
const ChannelReg = enum(u32) {
    DChcr = 0x1000_0000,
    DMadr = 0x1000_0010,
    DQwc  = 0x1000_0020,
    DTadr = 0x1000_0030,
    DAsr0 = 0x1000_0040,
    DAsr1 = 0x1000_0050,
    DSadr = 0x1000_0080,
};

/// DMA control registers
const ControlReg = enum(u32) {
    DCtrl = 0x1000_E000,
    DStat = 0x1000_E010,
    DPcr  = 0x1000_E020,
    DSqwc = 0x1000_E030,
    DRbsr = 0x1000_E040,
    DRbor = 0x1000_E050,
};

/// Returns the DMA channel number
fn getChannel(addr: u8) Channel {
    var chn: Channel = undefined;

    switch (addr) {
        0x80 => chn = Channel.Vif0,
        0x90 => chn = Channel.Vif1,
        0xA0 => chn = Channel.Path3,
        0xB0 => chn = Channel.IpuFrom,
        0xB4 => chn = Channel.IpuTo,
        0xC0 => chn = Channel.Sif0,
        0xC4 => chn = Channel.Sif1,
        0xC8 => chn = Channel.Sif2,
        0xD0 => chn = Channel.SprFrom,
        0xD4 => chn = Channel.SprTo,
        else => {
            err("  [DMAC      ] Unhandled channel 0x{X:0>2}.", .{addr});

            assert(false);
        }
    }

    return chn;
}

/// Reads data from DMAC I/O
pub fn read(addr: u32) u32 {
    var data: u32 = 0;

    if (addr < @enumToInt(ControlReg.DCtrl)) {
        err("  [DMAC      ] Unhandled read @ 0x{X:0>8}.", .{addr});

        assert(false);
    } else {
        switch (addr) {
            @enumToInt(ControlReg.DStat) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D_STAT).", .{addr});
            },
            @enumToInt(ControlReg.DPcr) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D_PCR).", .{addr});
            },
            else => {
                err("  [DMAC      ] Unhandled read @ 0x{X:0>8}.", .{addr});

                assert(false);
            }
        }
    }

    return data;
}

/// Writes data to DMAC I/O
pub fn write(addr: u32, data: u32) void {
    if (addr < @enumToInt(ControlReg.DCtrl)) {
        const chn = getChannel(@truncate(u8, addr >> 8));

        switch (addr & ~@as(u32, 0xFF00)) {
            @enumToInt(ChannelReg.DChcr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_CTRL) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            @enumToInt(ChannelReg.DMadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_MADR) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            @enumToInt(ChannelReg.DQwc) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_QWC) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            @enumToInt(ChannelReg.DTadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_TADR) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            @enumToInt(ChannelReg.DAsr0) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_ASR0) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            @enumToInt(ChannelReg.DAsr1) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_ASR1) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            @enumToInt(ChannelReg.DSadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_SADR) = 0x{X:0>8}.", .{addr, @enumToInt(chn), data});
            },
            else => {
                err("  [DMAC      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

                assert(false);
            }
        }
    } else {
        switch (addr) {
            @enumToInt(ControlReg.DCtrl) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_CTRL) = 0x{X:0>8}.", .{addr, data});
            },
            @enumToInt(ControlReg.DStat) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_STAT) = 0x{X:0>8}.", .{addr, data});
            },
            @enumToInt(ControlReg.DPcr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_PCR) = 0x{X:0>8}.", .{addr, data});
            },
            @enumToInt(ControlReg.DSqwc) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_SQWC) = 0x{X:0>8}.", .{addr, data});
            },
            @enumToInt(ControlReg.DRbsr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_RBSR) = 0x{X:0>8}.", .{addr, data});
            },
            @enumToInt(ControlReg.DRbor) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_RBOR) = 0x{X:0>8}.", .{addr, data});
            },
            else => {
                err("  [DMAC      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

                assert(false);
            }
        }
    }
}
