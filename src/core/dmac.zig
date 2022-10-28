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

const bus = @import("bus.zig");
const sif = @import("sif.zig");

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

/// DMA direction
const Direction = enum(u1) {
    To, From,
};

/// DMA mode
const Mode = enum(u2) {
    Normal,
    Chain,
    Interleave,
};

/// Channel Control
const ChannelControl = struct {
    dir: u1   = undefined, // DIRection
    mod: u2   = undefined, // MODe
    asp: u2   = undefined, // Address Stack Pointer
    tte: bool = undefined, // Transfer DMAtag
    tie: bool = undefined, // Enable DMAtag IRQ bit
    str: bool = undefined, // STaRt
    tag: u16  = undefined, // DMAtag[16:31]

    req: bool = false, // DMA requested

    /// Returns CHCR
    pub fn get(self: ChannelControl) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.dir);
        data |= @as(u32, self.mod) << 2;
        data |= @as(u32, self.asp) << 4;
        data |= @as(u32, @bitCast(u1, self.tte)) << 6;
        data |= @as(u32, @bitCast(u1, self.tie)) << 7;
        data |= @as(u32, @bitCast(u1, self.str)) << 8;
        data |= @as(u32, self.tag) << 16;

        return data;
    }

    /// Sets CHCR
    pub fn set(self: *ChannelControl, data: u32) void {
        self.dir = @truncate(u1, data);
        self.mod = @truncate(u2, data >> 2);
        self.asp = @truncate(u2, data >> 4);
        self.tte = (data & (1 << 6)) != 0;
        self.tie = (data & (1 << 7)) != 0;
        self.str = (data & (1 << 8)) != 0;
    }
};

/// DMA channel
const DmaChannel = struct {
    chcr: ChannelControl = ChannelControl{},
    madr: u32            = undefined, // Memory ADdress Register
    tadr: u32            = undefined, // Tag ADdress Register
     qwc: u16            = undefined, // QuadWord Count
    asr0: u32            = undefined, // Address Stack Register 0
    asr1: u32            = undefined, // Address Stack Register 1
    sadr: u32            = undefined, // Scratchpad ADdress Register
};

/// DMAtags
const Tag = enum(u3) {
    Refe,
    Cnt,
    Next,
    Ref,
    Refs,
    Call,
    Ret,
    End,
};

var channels: [10]DmaChannel = undefined;

var dmaEnable = false;

/// Initializes the DMAC module
pub fn init() void {
    // Set SIF1 request bit for first transfer
    channels[@enumToInt(Channel.Sif1)].chcr.req = true;
}

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
        const chn = @enumToInt(getChannel(@truncate(u8, addr >> 8)));

        switch (addr & ~@as(u32, 0xFF00)) {
            @enumToInt(ChannelReg.DChcr) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_CTRL).", .{addr, chn});

                data = channels[chn].chcr.get();
            },
            @enumToInt(ChannelReg.DMadr) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_MADR).", .{addr, chn});

                data = channels[chn].madr;
            },
            @enumToInt(ChannelReg.DQwc) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_QWC).", .{addr, chn});

                data = @as(u32, channels[chn].qwc);
            },
            @enumToInt(ChannelReg.DTadr) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_TADR).", .{addr, chn});

                data = channels[chn].tadr;
            },
            @enumToInt(ChannelReg.DAsr0) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_ASR0).", .{addr, chn});

                data = channels[chn].asr0;
            },
            @enumToInt(ChannelReg.DAsr1) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_ASR1).", .{addr, chn});

                data = channels[chn].asr1;
            },
            @enumToInt(ChannelReg.DSadr) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D{}_SADR).", .{addr, chn});

                data = channels[chn].sadr;
            },
            else => {
                err("  [DMAC      ] Unhandled read @ 0x{X:0>8}.", .{addr});

                assert(false);
            }
        }
    } else {
        switch (addr) {
            @enumToInt(ControlReg.DCtrl) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D_CTRL).", .{addr});
            },
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
        const chn = @enumToInt(getChannel(@truncate(u8, addr >> 8)));

        switch (addr & ~@as(u32, 0xFF00)) {
            @enumToInt(ChannelReg.DChcr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_CTRL) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].chcr.set(data);

                checkRunning();
            },
            @enumToInt(ChannelReg.DMadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_MADR) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].madr = data;

                if (chn == 6 and data != 0) assert(false);
            },
            @enumToInt(ChannelReg.DQwc) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_QWC) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].qwc = @truncate(u16, data);
            },
            @enumToInt(ChannelReg.DTadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_TADR) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].tadr = data;
            },
            @enumToInt(ChannelReg.DAsr0) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_ASR0) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].asr0 = data;
            },
            @enumToInt(ChannelReg.DAsr1) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_ASR1) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].asr1 = data;
            },
            @enumToInt(ChannelReg.DSadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_SADR) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].sadr = data;
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

                dmaEnable = (data & 1) != 0;

                if (dmaEnable) {
                    checkRunning();
                }
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

/// Checks if DMA transfer is running
fn checkRunning() void {
    if (!dmaEnable) return;

    var chnId: u4 = 0;
    while (chnId < 10) : (chnId += 1) {
        if (channels[chnId].chcr.str and channels[chnId].chcr.req) {
            const chn = @intToEnum(Channel, chnId);

            if (chn == Channel.Sif1) {
                info("   [DMAC      ] Channel {} ({s}) transfer.", .{chnId, @tagName(chn)});

                assert(channels[chnId].chcr.mod < 3);

                const mode = @intToEnum(Mode, channels[chnId].chcr.mod);

                switch (mode) {
                    Mode.Chain => doChain(chn),
                    else => {
                        err("  [DMAC      ] Unhandled {s} mode transfer.", .{@tagName(mode)});

                        assert(false);
                    }
                }
            } else {
                err("  [DMAC      ] Unhandled channel {} ({s}) transfer.", .{chnId, @tagName(chn)});

                assert(false);
            }
        }
    }
}

/// Performs a chain transfer
fn doChain(chn: Channel) void {
    const chnId = @enumToInt(chn);

    const dir = @intToEnum(Direction, channels[chnId].chcr.dir);
    const isSrc = if (dir == Direction.To) "Source" else "Destination";

    info("   [DMAC      ] {s} Chain mode. Tag address = 0x{X:0>8}", .{isSrc, channels[chnId].tadr});

    if (channels[chnId].qwc != 0) {
        assert(false);
    }

    var tadr = channels[chnId].tadr;

    var tagEnd = false;

    while (true) {
        var dmaTag: u128 = undefined;
        
        if (dir == Direction.To) {
            dmaTag = bus.readDmac(tadr);
        } else {
            err("  [DMAC      ] Unhandled Destination Chain transfer.", .{});

            assert(false);
        }

        info("   [DMAC      ] Tag = 0x{X:0>16}", .{dmaTag});

        channels[chnId].chcr.tag = @truncate(u16, dmaTag >> 16);

        const tagId = @truncate(u3, dmaTag >> 28);

        var qwc  = @truncate(u16, dmaTag);
        var madr: u32 = undefined;

        switch (tagId) {
            @enumToInt(Tag.Refe) => {
                madr = @truncate(u32, dmaTag >> 32);

                info("   [DMAC      ] New tag: refe. MADR = 0x{X:0>8}, QWC = {}", .{madr, qwc});

                tagEnd = true;
            },
            else => {
                const tag = @intToEnum(Tag, tagId);

                err("  [DMAC      ] Unhandled tag {s}.", .{@tagName(tag)});

                assert(false);
            }
        }

        if (channels[chnId].chcr.tte) {
            err("  [DMAC      ] Unhandled DMAtag transfer.", .{});

            assert(false);
        }

        while (qwc > 0) : (qwc -= 1) {
            if (dir == Direction.To) {
                switch (chn) {
                    Channel.Sif1 => sif.writeSif1(bus.readDmac(madr)),
                    else => {
                        err("  [DMAC      ] Unhandled {s} transfer.", .{@tagName(chn)});

                        assert(false);
                    }
                }
            } else {
                err("  [DMAC      ] Unhandled Destination Chain transfer.", .{});

                assert(false);
            }

            madr += @sizeOf(u128);
        }

        if (tagEnd) {
            switch (chn) {
                Channel.Sif1 => {
                    channels[chnId].chcr.req = false;

                    err("  [SIF (DMAC)] Unhandled IOP request.", .{});

                    assert(false);
                },
                else => {
                    err("  [DMAC      ] Unhandled {s} transfer.", .{@tagName(chn)});

                    assert(false);
                }
            }

            channels[chnId].chcr.str = false;

            break;
        }
    }
}
