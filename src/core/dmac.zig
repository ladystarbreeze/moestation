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

const bus     = @import("bus.zig");
const cop0    = @import("cop0.zig");
const dmacIop = @import("dmac_iop.zig");
const gif     = @import("gif.zig");
const sif     = @import("sif.zig");
const vif1    = @import("vif1.zig");

/// DMA channels
pub const Channel = enum(u4) {
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
    DCtrl  = 0x1000_E000,
    DStat  = 0x1000_E010,
    DPcr   = 0x1000_E020,
    DSqwc  = 0x1000_E030,
    DRbsr  = 0x1000_E040,
    DRbor  = 0x1000_E050,
    DStadr = 0x1000_E060,
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
    tagEnd: bool           = undefined,
    hasTag: bool           = false,
};

/// D_STAT register
const DmaStatus = struct {
     ip: u10  = undefined, // Interrupt Pending
     ds: bool = undefined, // DMA Stall interrupt
     mf: bool = undefined, // MFIFO empty interrupt
     be: bool = undefined, // Bus Error interrupt
     im: u10  = 0,         // Interrupt Mask
    dsm: bool = undefined, // DMA Stall Mask
    mfm: bool = undefined, // MFIFO empty Mask

    /// Returns D_STAT
    pub fn get(self: DmaStatus) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.ip);
        data |= @as(u32, @bitCast(u1, self.ds)) << 13;
        data |= @as(u32, @bitCast(u1, self.mf)) << 14;
        data |= @as(u32, @bitCast(u1, self.be)) << 15;
        data |= @as(u32, self.im) << 16;
        data |= @as(u32, @bitCast(u1, self.dsm)) << 29;
        data |= @as(u32, @bitCast(u1, self.mfm)) << 30;

        return data;
    }

    /// Sets D_STAT
    pub fn set(self: *DmaStatus, data: u32) void {
        self.ip &= ~@truncate(u10, data);
        self.ds  = (data & (1 << 13)) != 0;
        self.mf  = (data & (1 << 14)) != 0;
        self.be  = (data & (1 << 15)) != 0;
        self.im ^= @truncate(u10, data >> 16);
        self.dsm = (data & (1 << 29)) != 0;
        self.mfm = (data & (1 << 30)) != 0;
    }
};

/// D_PCR
const PriorityControl = struct {
    cpc: u10  = 0,
    cde: u10  = 0,
    pce: bool = false,

    /// Returns D_PCR
    pub fn get(self: PriorityControl) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.cpc);
        data |= @as(u32, self.cde) << 16;
        data |= @as(u32, @bitCast(u1, self.pce)) << 31;

        return data;
    }

    /// Sets D_PCR
    pub fn set(self: *PriorityControl, data: u32) void {
        self.cpc = @truncate(u10, data);
        self.cde = @truncate(u10, data >> 16);
        self.pce = (data & (1 << 31)) != 0;
    }
};

/// Source Chain tags
const SourceTag = enum(u3) {
    Refe,
    Cnt,
    Next,
    Ref,
    Refs,
    Call,
    Ret,
    End,
};

/// Destination Chain tags
const DestTag = enum(u3) {
    Cnt,
    Cnts,
    End = 7,
};

var channels: [10]DmaChannel = undefined;

var dStat: DmaStatus = DmaStatus{};
var  dPcr: PriorityControl = PriorityControl{};

var dEnable: u32 = 0x1201;
var   dctrl: u32 = undefined;

/// Initializes the DMAC module
pub fn init() void {
    channels[@enumToInt(Channel.Vif0)   ].chcr.req = true;
    channels[@enumToInt(Channel.Vif1)   ].chcr.req = true;
    channels[@enumToInt(Channel.IpuTo)  ].chcr.req = true;
    channels[@enumToInt(Channel.IpuTo)  ].chcr.req = true;
    channels[@enumToInt(Channel.Sif1)   ].chcr.req = true;
    channels[@enumToInt(Channel.SprFrom)].chcr.req = true;
    channels[@enumToInt(Channel.SprTo)  ].chcr.req = true;
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

                data = dctrl;
            },
            @enumToInt(ControlReg.DStat) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D_STAT).", .{addr});

                data = dStat.get();
            },
            @enumToInt(ControlReg.DPcr) => {
                info("   [DMAC      ] Read @ 0x{X:0>8} (D_PCR).", .{addr});

                data = dPcr.get();
            },
            @enumToInt(ControlReg.DSqwc) => {
                warn("[DMAC      ] Read @ 0x{X:0>8} (D_SQWC).", .{addr});

                data = 0;
            },
            @enumToInt(ControlReg.DRbsr) => {
                warn("[DMAC      ] Read @ 0x{X:0>8} (D_RBSR).", .{addr});

                data = 0;
            },
            @enumToInt(ControlReg.DRbor) => {
                warn("[DMAC      ] Read @ 0x{X:0>8} (D_RBOR).", .{addr});

                data = 0;
            },
            @enumToInt(ControlReg.DStadr) => {
                warn("[DMAC      ] Read @ 0x{X:0>8} (D_STADR).", .{addr});

                data = 0;
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
            },
            @enumToInt(ChannelReg.DMadr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D{}_MADR) = 0x{X:0>8}.", .{addr, chn, data});

                channels[chn].madr = data;
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

                dctrl = data;
            },
            @enumToInt(ControlReg.DStat) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_STAT) = 0x{X:0>8}.", .{addr, data});

                dStat.set(data);

                checkInterrupt();
            },
            @enumToInt(ControlReg.DPcr) => {
                info("   [DMAC      ] Write @ 0x{X:0>8} (D_PCR) = 0x{X:0>8}.", .{addr, data});

                dPcr.set(data);
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

/// Returns coprocessor 0 signal
pub fn getCpcond0() bool {
    return (~dPcr.cpc | dStat.ip) == 0x3FF;
}

/// Returns D_ENABLER
pub fn getEnable() u32 {
    return dEnable;
}

/// Sets D_ENABLEW
pub fn setEnable(data: u32) void {
    dEnable = data;

    checkRunning();
}

/// Sets request flag
pub fn setRequest(chn: Channel, req: bool) void {
    if (!channels[@enumToInt(chn)].chcr.req and req) {
        // info("   [DMAC      ] {s} DMA requested.", .{@tagName(chn)});
    }

    channels[@enumToInt(chn)].chcr.req = req;
}

/// Sets interrupt flag
fn transferEnd(chnId: u4) void {
    info("   [DMAC      ] Channel {} transfer end.", .{chnId});

    channels[chnId].tagEnd = false;
    channels[chnId].hasTag = false;

    dStat.ip |= @as(u10, 1) << chnId;

    checkInterrupt();
}

/// Checks for DMA interrupts
fn checkInterrupt() void {
    info("   [DMAC      ] IM = 0b{b:0>10}, IP = 0b{b:0>10}", .{dStat.im, dStat.ip});

    cop0.setDmacIrqPending((dStat.im & dStat.ip) != 0);
}

/// Checks if DMA transfer is running
pub fn checkRunning() void {
    if ((dEnable & (1 << 16)) != 0 or (dctrl & 1) == 0) return;

    var chnId: u4 = 0;
    while (chnId < 10) : (chnId += 1) {
        if (channels[chnId].chcr.str and channels[chnId].chcr.req) {
            const chn = @intToEnum(Channel, chnId);

            switch (chn) {
                Channel.Vif1  => doVif1(),
                Channel.Path3 => doPath3(),
                Channel.Sif0  => doSif0(),
                Channel.Sif1  => doSif1(),
                else => {
                    err("  [DMAC      ] Unhandled channel {} ({s}) transfer.", .{chnId, @tagName(chn)});

                    assert(false);
                }
            }

            return;
        }
    }
}

/// Decodes a Source Chain DMAtag
fn decodeSourceTag(chnId: u4, dmaTag: u128) void {
    info("   [DMAC      ] Source Chain tag = 0x{X:0>32}", .{dmaTag});

    channels[chnId].chcr.tag = @truncate(u16, dmaTag >> 16);
    channels[chnId].qwc = @truncate(u16, dmaTag);

    const tag = @intToEnum(SourceTag, @truncate(u3, dmaTag >> 28));

    switch (tag) {
        SourceTag.Refe => {
            channels[chnId].madr  = @truncate(u32, dmaTag >> 32);
            channels[chnId].tadr += @sizeOf(u128);

            info("   [DMAC      ] New tag: refe. MADR = 0x{X:0>8}, TADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].tadr, channels[chnId].qwc});

            channels[chnId].tagEnd = true;
        },
        SourceTag.Cnt => {
            channels[chnId].madr = channels[chnId].tadr + @sizeOf(u128);
            channels[chnId].tadr = channels[chnId].madr + @sizeOf(u128) * channels[chnId].qwc;

            info("   [DMAC      ] New tag: cnt. MADR = 0x{X:0>8}, TADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].tadr, channels[chnId].qwc});

            channels[chnId].tagEnd = (dmaTag & (1 << 31)) != 0 and channels[chnId].chcr.tie;
        },
        SourceTag.Next => {
            channels[chnId].madr = channels[chnId].tadr + @sizeOf(u128);
            channels[chnId].tadr = @truncate(u32, dmaTag >> 32);

            info("   [DMAC      ] New tag: next. MADR = 0x{X:0>8}, TADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].tadr, channels[chnId].qwc});

            channels[chnId].tagEnd = (dmaTag & (1 << 31)) != 0 and channels[chnId].chcr.tie;
        },
        SourceTag.Ref => {
            channels[chnId].madr  = @truncate(u32, dmaTag >> 32);
            channels[chnId].tadr += @sizeOf(u128);

            info("   [DMAC      ] New tag: ref. MADR = 0x{X:0>8}, TADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].tadr, channels[chnId].qwc});

            channels[chnId].tagEnd = (dmaTag & (1 << 31)) != 0 and channels[chnId].chcr.tie;
        },
        SourceTag.Refs => {
            // TODO: stalls
            channels[chnId].madr  = @truncate(u32, dmaTag >> 32);
            channels[chnId].tadr += @sizeOf(u128);

            info("   [DMAC      ] New tag: refs. MADR = 0x{X:0>8}, TADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].tadr, channels[chnId].qwc});

            channels[chnId].tagEnd = (dmaTag & (1 << 31)) != 0 and channels[chnId].chcr.tie;
        },
        SourceTag.End => {
            channels[chnId].madr = channels[chnId].tadr + @sizeOf(u128);
            //channels[chnId].tadr += @sizeOf(u128);

            info("   [DMAC      ] New tag: end. MADR = 0x{X:0>8}, TADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].tadr, channels[chnId].qwc});

            channels[chnId].tagEnd = true;
        },
        else => {
            err("  [DMAC      ] Unhandled Source Chain tag {s}.", .{@tagName(tag)});

            assert(false);
        }
    }
}

/// Decodes a Destination Chain tag
fn decodeDestTag(chnId: u4, dmaTag: u128) void {
    info("   [DMAC      ] Destination Chain tag = 0x{X:0>32}", .{dmaTag});

    channels[chnId].chcr.tag = @truncate(u16, dmaTag >> 16);
    channels[chnId].qwc = @truncate(u16, dmaTag);

    const tag = @truncate(u3, dmaTag >> 28);

    switch (tag) {
        @enumToInt(DestTag.Cnt) => {
            channels[chnId].madr = @truncate(u32, dmaTag >> 32);

            info("   [DMAC      ] New tag: cnt. MADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].qwc});

            channels[chnId].tagEnd = (dmaTag & (1 << 31)) != 0 and channels[chnId].chcr.tie;
        },
        @enumToInt(DestTag.Cnts) => {
            channels[chnId].madr = @truncate(u32, dmaTag >> 32);

            info("   [DMAC      ] New tag: cnts. MADR = 0x{X:0>8}, QWC = {}", .{channels[chnId].madr, channels[chnId].qwc});

            channels[chnId].tagEnd = (dmaTag & (1 << 31)) != 0 and channels[chnId].chcr.tie;
        },
        else => {
            err("  [DMAC      ] Unhandled Destination Chain tag {}.", .{tag});

            assert(false);
        }
    }
}

/// Performs a PATH3 transfer
fn doPath3() void {
    const chnId = @enumToInt(Channel.Path3);

    if (channels[chnId].chcr.dir != @enumToInt(Direction.From)) {
        err("  [DMAC      ] Unhandled PATH3 direction.", .{});

        assert(false);
    }

    if (channels[chnId].qwc == 0) {
        assert(channels[chnId].chcr.mod < 2);

        if (channels[chnId].chcr.mod == @enumToInt(Mode.Normal)) {
            channels[chnId].chcr.str = false;

            return transferEnd(chnId);
        }

        info("   [DMAC      ] Channel {} ({s}) transfer, Source Chain mode.", .{chnId, @tagName(Channel.Path3)});

        // Read new tag
        const dmaTag = bus.readDmac(channels[chnId].tadr);

        decodeSourceTag(chnId, dmaTag);

        channels[chnId].hasTag = true;

        if (channels[chnId].chcr.tte) {
            info("  [DMAC      ] Unhandled tag transfer.", .{});
            
            assert(false);
        }

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    } else {
        if (!channels[chnId].hasTag) {
            //info("   [DMAC      ] Channel {} ({s}) transfer, no tag.", .{chnId, @tagName(Channel.Path3)});
        }

        channels[chnId].qwc -= 1;

        gif.writePath3(bus.readDmac(channels[chnId].madr & 0xFFFF_FFF0));

        channels[chnId].madr += @sizeOf(u128);
        
        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    }
}

/// Performs a SIF0 transfer
fn doSif0() void {
    const chnId = @enumToInt(Channel.Sif0);

    if (channels[chnId].qwc == 0) {
        info("   [DMAC      ] Channel {} ({s}) transfer, Destination Chain mode.", .{chnId, @tagName(Channel.Sif0)});

        // Read new tag
        const dmaTag = @as(u128, sif.readSif0(u64));

        decodeDestTag(chnId, dmaTag);

        if (channels[chnId].chcr.tte) {
            info("  [DMAC      ] Unhandled tag transfer.", .{});
            
            assert(false);
        }

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    } else {
        channels[chnId].qwc -= 1;

        bus.writeDmac(channels[chnId].madr, sif.readSif0(u128));

        channels[chnId].madr += @sizeOf(u128);

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    }
}

/// Performs a SIF1 transfer
fn doSif1() void {
    const chnId = @enumToInt(Channel.Sif1);

    if (channels[chnId].qwc == 0) {
        info("   [DMAC      ] Channel {} ({s}) transfer, Source Chain mode.", .{chnId, @tagName(Channel.Sif1)});
        //std.debug.print("EE SIF1 start\n", .{});

        // Read new tag
        const dmaTag = bus.readDmac(channels[chnId].tadr);

        decodeSourceTag(chnId, dmaTag);

        channels[chnId].hasTag = true;

        if (channels[chnId].chcr.tte) {
            info("  [DMAC      ] Unhandled tag transfer.", .{});
            
            assert(false);
        }

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    } else {
        if (!channels[chnId].hasTag) {
            assert(false);
        }

        channels[chnId].qwc -= 1;

        sif.writeSif1(bus.readDmac(channels[chnId].madr));
        
        channels[chnId].madr += @sizeOf(u128);

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    }
}

/// Performs a VIF1 transfer
fn doVif1() void {
    const chnId = @enumToInt(Channel.Vif1);

    if (channels[chnId].qwc == 0) {
        info("   [DMAC      ] Channel {} ({s}) transfer, Source Chain mode.", .{chnId, @tagName(Channel.Vif1)});

        // Read new tag
        const dmaTag = bus.readDmac(channels[chnId].tadr);

        decodeSourceTag(chnId, dmaTag);

        channels[chnId].hasTag = true;

        if (channels[chnId].chcr.tte) {
            vif1.writeFifo(dmaTag >> 64);
        }

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    } else {
        if (!channels[chnId].hasTag) {
            assert(false);
        }

        channels[chnId].qwc -= 1;

        vif1.writeFifo(bus.readDmac(channels[chnId].madr));
        
        channels[chnId].madr += @sizeOf(u128);

        if (channels[chnId].qwc == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    }
}
