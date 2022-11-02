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

const cdvd = @import("cdvd.zig");

const Direction = @import("dmac.zig").Direction;

const intc = @import("intc.zig");

const sif = @import("sif.zig");

/// DMA channels
pub const Channel = enum(u4) {
    MdecIn,
    MdecOut,
    Sif2,
    Cdvd,
    Spu1,
    Pio,
    Otc,
    Spu2,
    Dev9,
    Sif0,
    Sif1,
    Sio2In,
    Sio2Out,
    None,
};

/// DMA channel registers
const ChannelReg = enum(u32) {
    DMadr = 0x1F80_1000,
    DBcr  = 0x1F80_1004,
    DChcr = 0x1F80_1008,
    DTadr = 0x1F80_100C,
};

/// DMA control registers
const ControlReg = enum(u32) {
    Dpcr      = 0x1F80_10F0,
    Dicr      = 0x1F80_10F4,
    Dpcr2     = 0x1F80_1570,
    Dicr2     = 0x1F80_1574,
    DmacEn    = 0x1F80_1578,
    DmacIntEn = 0x1F80_157C,
};

/// DMA mode
const Mode = enum(u2) {
    Burst,
    Slice,
    LinkedList,
    Chain,
};

/// Block Count register
const BlockCount = struct {
     size: u16 = undefined,
    count: u16 = undefined,
      len: u32 = 0,

    /// Returns BCR
    pub fn get(self: BlockCount) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.size);
        data |= @as(u32, self.count) << 16;

        return data;
    }

    /// Sets BCR
    pub fn set(self: *BlockCount, data: u32) void {
        self.size  = @truncate(u16, data);
        self.count = @truncate(u16, data >> 16);
    }
};

/// Channel Control register
const ChannelControl = struct {
    dir: u1   = undefined,
    inc: bool = undefined, // Increment
    tte: bool = undefined, // Transfer Tag
    mod: u2   = undefined,
    cpd: u3   = undefined, // ChoPping DMA window size
    cpc: u3   = undefined, // ChoPping CPU window size
    str: bool = undefined, // STaRt
    fst: bool = undefined, // Forced STart

    req: bool = undefined, // REQuest

    /// Returns CHCR
    pub fn get(self: ChannelControl) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.dir);
        data |= @as(u32, @bitCast(u1, self.inc)) << 1;
        data |= @as(u32, @bitCast(u1, self.inc)) << 8;
        data |= @as(u32, self.mod) << 9;
        data |= @as(u32, self.cpd) << 16;
        data |= @as(u32, self.cpc) << 20;
        data |= @as(u32, @bitCast(u1, self.str)) << 24;
        data |= @as(u32, @bitCast(u1, self.fst)) << 28;

        return data;
    }

    /// Sets CHCR
    pub fn set(self: *ChannelControl, data: u32) void {
        self.dir = @truncate(u1, data);
        self.inc = (data & (1 << 1)) != 0;
        self.tte = (data & (1 << 8)) != 0;
        self.mod = @truncate(u2, data >> 9);
        self.cpd = @truncate(u3, data >> 16);
        self.cpc = @truncate(u3, data >> 20);
        self.str = (data & (1 << 24)) != 0;
        self.fst = (data & (1 << 28)) != 0;
    }
};

/// DMA channel
const DmaChannel = struct {
      madr: u24            = undefined, // Memory ADdress Register
       bcr: BlockCount     = undefined, // Block Count Register
      chcr: ChannelControl = undefined,
      tadr: u24            = undefined, // Tag ADdress Register
    tagEnd: bool           = false,
};

/// DMA Interrupt Control Register
const Dicr = struct {
    sie: u7   = undefined, // Slice Interrupt Enable
     be: bool = undefined, // Bus Error
     im: u7   = undefined, // Interrupt Mask
    mie: bool = undefined, // Master channel Interrupt Enable
     ip: u7   = undefined, // Interrupt Pending
    mif: bool = undefined, // Master Interrupt Flag

    /// Returns DICR
    pub fn get(self: Dicr) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.sie);
        data |= @as(u32, @bitCast(u1, self.be)) << 15;
        data |= @as(u32, self.im) << 16;
        data |= @as(u32, @bitCast(u1, self.mie)) << 23;
        data |= @as(u32, self.ip) << 24;
        data |= @as(u32, @bitCast(u1, self.mif)) << 31;

        return data;
    }

    /// Sets DICR
    pub fn set(self: *Dicr, data: u32) void {
        self.sie =  @truncate(u7, data);
        self.be  =  (data & (1 << 15)) != 0;
        self.im  =  @truncate(u7, data >> 16);
        self.mie =  (data & (1 << 23)) != 0;
        self.ip &= ~@truncate(u7, data >> 24);
    }
};

/// DMA Interrupt Control Register 2
const Dicr2 = struct {
    tie: u12 = undefined, // Tag Interrupt Enable
     im: u6  = undefined, // Interrupt Mask
     ip: u6  = undefined, // Interrupt Pending

    /// Returns DICR2
    pub fn get(self: Dicr2) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.tie);
        data |= @as(u32, self.im) << 16;
        data |= @as(u32, self.ip) << 24;

        return data;
    }

    /// Sets DICR2
    pub fn set(self: *Dicr2, data: u32) void {
        self.tie &= ~@truncate(u12, data);
        self.im   =  @truncate(u6, data >> 16);
        self.ip  &= ~@truncate(u6, data >> 24);
    }
};

/// Global DMA Interrupt Control
const DmacIntEn = struct {
    cie: bool = undefined, // Channel Interrupt Enable
    mid: bool = undefined, // Master Interrupt Disable

    /// Returns DMACINTEN
    pub fn get(self: DmacIntEn) u32 {
        var data: u32 = 0;

        data |= @as(u32, @bitCast(u1, self.cie));
        data |= @as(u32, @bitCast(u1, self.mid)) << 1;

        return data;
    }

    /// Sets DMACINTEN
    pub fn set(self: *DmacIntEn, data: u32) void {
        self.cie = (data & 1) != 0;
        self.mid = (data & (1 << 1)) != 0;
    }
};

var channels: [14]DmaChannel = undefined; // BIOS initializes 14 channels?

/// DMA control registers
var  dpcr: u32 = undefined;
var dpcr2: u32 = undefined;

var  dicr: Dicr  = Dicr{};
var dicr2: Dicr2 = Dicr2{};

var    dmacEn: bool      = false;
var dmacIntEn: DmacIntEn = DmacIntEn{};

/// Initializes DMA module
pub fn init() void {
    // Set SIF0 request bit for first transfer
    channels[@enumToInt(Channel.Sif0)].chcr.req = true;
}

/// Returns the DMA channel number
fn getChannel(addr: u8) Channel {
    var chn: Channel = undefined;

    switch (addr) {
        0x08 => chn = Channel.MdecIn,
        0x09 => chn = Channel.MdecOut,
        0x0A => chn = Channel.Sif2,
        0x0B => chn = Channel.Cdvd,
        0x0C => chn = Channel.Spu1,
        0x0D => chn = Channel.Pio,
        0x0E => chn = Channel.Otc,
        0x50 => chn = Channel.Spu2,
        0x51 => chn = Channel.Dev9,
        0x52 => chn = Channel.Sif0,
        0x53 => chn = Channel.Sif1,
        0x54 => chn = Channel.Sio2In,
        0x55 => chn = Channel.Sio2Out,
        else => chn = Channel.None,
    }

    return chn;
}

/// Reads data from DMAC I/O
pub fn read(addr: u32) u32 {
    var data: u32 = undefined;

    if (addr < @enumToInt(ControlReg.Dpcr) or (addr > @enumToInt(ControlReg.Dicr) and addr < @enumToInt(ControlReg.Dpcr2))) {
        const chn = @enumToInt(getChannel(@truncate(u8, addr >> 4)));

        switch (addr & ~@as(u32, 0xFF0)) {
            @enumToInt(ChannelReg.DChcr) => {
                info("   [DMAC (IOP)] Read @ 0x{X:0>8} (D{}_CHCR).", .{addr, chn});

                data = channels[chn].chcr.get();
            },
            else => {
                err("  [DMAC (IOP)] Unhandled read @ 0x{X:0>8}.", .{addr});

                assert(false);
            }
        }
    } else {
        switch (addr) {
            @enumToInt(ControlReg.Dpcr) => {
                info("   [DMAC (IOP)] Read @ 0x{X:0>8} (DPCR).", .{addr});

                data = dpcr;
            },
            @enumToInt(ControlReg.Dicr) => {
                info("   [DMAC (IOP)] Read @ 0x{X:0>8} (DICR).", .{addr});

                data = dicr.get();
            },
            @enumToInt(ControlReg.Dpcr2) => {
                info("   [DMAC (IOP)] Read @ 0x{X:0>8} (DPCR2).", .{addr});

                data = dpcr2;
            },
            @enumToInt(ControlReg.Dicr2) => {
                info("   [DMAC (IOP)] Read @ 0x{X:0>8} (DICR2).", .{addr});

                data = dicr2.get();
            },
            @enumToInt(ControlReg.DmacEn) => {
                info("   [DMAC (IOP)] Read @ 0x{X:0>8} (DMACEN).", .{addr});

                data = @as(u32, @bitCast(u1, dmacEn));
            },
            else => {
                err("  [DMAC (IOP)] Unhandled control read @ 0x{X:0>8}.", .{addr});

                assert(false);
            }
        }
    }

    return data;
}

/// Writes data to DMAC I/O
pub fn write(comptime T: type, addr: u32, data: T) void {
    if (addr < @enumToInt(ControlReg.Dpcr) or (addr > @enumToInt(ControlReg.Dicr) and addr < @enumToInt(ControlReg.Dpcr2))) {
        const chn = @enumToInt(getChannel(@truncate(u8, addr >> 4)));

        switch (addr & ~@as(u32, 0xFF3)) {
            @enumToInt(ChannelReg.DMadr) => {
                if (T != u32) {
                    @panic("Unhandled write @ D_MADR");
                }

                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (D{}_MADR) = 0x{X:0>8}.", .{@typeName(T), addr, chn, data});

                channels[chn].madr = @truncate(u24, data);
            },
            @enumToInt(ChannelReg.DBcr) => {
                const offset = @truncate(u2, addr);

                switch (T) {
                     u8 => @panic("Unhandled write @ D_BCR"),
                    u16 => {
                        if ((offset & 1) == 0) {
                            channels[chn].bcr.size = @truncate(u16, data);
                        } else {
                            channels[chn].bcr.count = @truncate(u16, data);
                        }
                    },
                     u32 => channels[chn].bcr.set(data),
                    else => unreachable,
                }

                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (D{}_BCR) = 0x{X:0>8}.", .{@typeName(T), addr, chn, data});
            },
            @enumToInt(ChannelReg.DChcr) => {
                if (T != u32) {
                    @panic("Unhandled write @ D_CHCR");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (D{}_CHCR) = 0x{X:0>8}.", .{@typeName(T), addr, chn, data});

                channels[chn].chcr.set(data);
            },
            @enumToInt(ChannelReg.DTadr) => {
                if (T != u32) {
                    @panic("Unhandled write @ D_TADR");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (D{}_TADR) = 0x{X:0>8}.", .{@typeName(T), addr, chn, data});

                channels[chn].tadr = @truncate(u24, data);
            },
            else => {
                err("  [DMAC (IOP)] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X:0>8}.", .{@typeName(T), addr, data});

                assert(false);
            },
        }
    } else {
        switch (addr) {
            @enumToInt(ControlReg.Dpcr) => {
                if (T != u32) {
                    @panic("Unhandled write @ DPCR");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (DPCR) = 0x{X:0>8}.", .{@typeName(T), addr, data});

                dpcr = data;
            },
            @enumToInt(ControlReg.Dicr) => {
                if (T != u32) {
                    @panic("Unhandled write @ DICR");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (DICR) = 0x{X:0>8}.", .{@typeName(T), addr, data});

                dicr.set(data);

                checkInterrupt();
            },
            @enumToInt(ControlReg.Dpcr2) => {
                if (T != u32) {
                    @panic("Unhandled write @ DPCR2");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (DPCR2) = 0x{X:0>8}.", .{@typeName(T), addr, data});

                dpcr2 = data;
            },
            @enumToInt(ControlReg.Dicr2) => {
                if (T != u32) {
                    @panic("Unhandled write @ DICR2");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (DICR2) = 0x{X:0>8}.", .{@typeName(T), addr, data});

                dicr2.set(data);

                checkInterrupt();
            },
            @enumToInt(ControlReg.DmacEn) => {
                if (T != u32) {
                    @panic("Unhandled write @ DMACEN");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (DMACEN) = 0x{X:0>8}.", .{@typeName(T), addr, data});

                dmacEn = (data & 1) != 0;
            },
            @enumToInt(ControlReg.DmacIntEn) => {
                if (T != u32) {
                    @panic("Unhandled write @ DMACINTEN");
                }
                
                info("   [DMAC (IOP)] Write ({s}) @ 0x{X:0>8} (DMACINTEN) = 0x{X:0>8}.", .{@typeName(T), addr, data});

                dmacIntEn.set(data);
            },
            else => {
                err("  [DMAC (IOP)] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X:0>8}.", .{@typeName(T), addr, data});

                assert(false);
            }
        }
    }
}

/// Sets request flag
pub fn setRequest(chn: Channel, req: bool) void {
    if (!channels[@enumToInt(chn)].chcr.req and req) {
        info("   [DMAC (IOP)] {s} DMA requested.", .{@tagName(chn)});
    }

    channels[@enumToInt(chn)].chcr.req = req;
}

/// Sets interrupt flag if not masked
fn transferEnd(chnId: u4) void {
    info("   [DMAC (IOP)] Channel {} transfer end.", .{chnId});

    //info("   [DMAC (IOP)] DICR = 0b{b:0>6}{b:0>7}", .{dicr2.im, dicr.im});

    if (chnId < 7) {
        if ((dicr.im & (@as(u7, 1) << @truncate(u3, chnId))) != 0) {
            dicr.ip |= @as(u7, 1) << @truncate(u3, chnId);
        }
    } else {
        if ((dicr2.im & (@as(u6, 1) << @truncate(u3, chnId - 7))) != 0) {
            dicr2.ip |= @as(u6, 1) << @truncate(u3, chnId - 7);
        }
    }

    checkInterrupt();
}

fn setTagInterrupt(chnId: u4) void {
    dicr2.tie |= @as(u12, 1) << chnId;

    checkInterrupt();
}

/// Checks for DMA interrupts
fn checkInterrupt() void {
    // NOTE: DobieStation ignores DMACEN and DMACINTEN, so we will do the same.

    //const oldMif = dicr.mif;

    //dicr.mif = dicr.be or (dmacIntEn.cie and dicr.mie and (dicr.ip | dicr2.ip) != 0);
    dicr.mif = dicr.be or (dicr.mie and (dicr.ip | dicr2.ip) != 0) or dicr2.tie != 0;

    //info("   [DMAC (IOP)] Master Interrupt Flag = {}, Channel Interrupt Enable = {}", .{dicr.mif, dmacIntEn.cie});
    info("   [DMAC (IOP)] Master Interrupt Flag = {}", .{dicr.mif});

    if (dicr.mif and !dmacIntEn.mid) {
        intc.sendInterruptIop(intc.IntSourceIop.Dma);
    }
}

/// Checks if DMA transfer is running
pub fn checkRunning() void {
    if (!dmacEn) return;

    var chnId: u4 = 0;
    while (chnId < 13) : (chnId += 1) {
        var cen: bool = undefined; 
        
        if (chnId < 7) {
            cen = (dpcr & (@as(u32, 1) << (4 * @as(u5, chnId) + 3))) != 0;
        } else {
            cen = (dpcr2 & (@as(u32, 1) << (4 * @as(u5, chnId - 7) + 3))) != 0;
        }

        if (cen and channels[chnId].chcr.str and channels[chnId].chcr.req) {
            const chn = @intToEnum(Channel, chnId);

            switch (chn) {
                Channel.Cdvd => doCdvd(),
                Channel.Sif0 => doSif0(),
                Channel.Sif1 => doSif1(),
                else => {
                    err("  [DMAC (IOP)] Unhandled channel {} ({s}) transfer.", .{chnId, @tagName(chn)});

                    assert(false);
                }
            }

            return;
        }
    }
}

/// Performs CDVD DMA
fn doCdvd() void {
    const chnId = @enumToInt(Channel.Cdvd);

    assert(channels[chnId].chcr.mod == @enumToInt(Mode.Slice));
    assert(!channels[chnId].chcr.inc);

    if (channels[chnId].bcr.len == 0) {
        info("   [DMAC (IOP)] Channel {} ({s}) transfer, Slice mode.", .{chnId, @tagName(Channel.Cdvd)});

        channels[chnId].bcr.len = @as(u32, channels[chnId].bcr.count) * @as(u32, channels[chnId].bcr.size);

        info("   [DMAC (IOP)] MADR = 0x{X:0>6}, WC = {}", .{channels[chnId].madr, channels[chnId].bcr.len});
    } else {
        channels[chnId].bcr.len -= 1;
        
        const data = cdvd.readDmac();

        bus.writeIopDmac(channels[chnId].madr, data);

        channels[chnId].madr +%= 4;

        if (channels[chnId].bcr.len == 0) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);

            cdvd.sendInterrupt();
        }
    }
}

/// Performs SIF0 DMA
fn doSif0() void {
    const chnId = @enumToInt(Channel.Sif0);

    assert(channels[chnId].chcr.mod == @enumToInt(Mode.Chain));
    assert(!channels[chnId].chcr.inc);
    assert(channels[chnId].chcr.tte);

    if (channels[chnId].bcr.count == 0) {
        info("   [DMAC (IOP)] Channel {} ({s}) transfer, Chain mode.", .{chnId, @tagName(Channel.Sif0)});

        // Read new tag
        const tag = @as(u64, bus.readDmacIop(channels[chnId].tadr)) | (@as(u64, bus.readDmacIop(channels[chnId].tadr + 4)) << 32);

        channels[chnId].tagEnd = (tag & (1 << 31)) != 0 or (tag & (1 << 30)) != 0;

        info("   [DMAC (IOP)] Tag = 0x{X:0>16} (Tag end = {})", .{tag, channels[chnId].tagEnd});

        channels[chnId].tadr += 8;

        if (channels[chnId].chcr.tte) {
            sif.writeSif0(bus.readDmacIop(channels[chnId].tadr));
            sif.writeSif0(bus.readDmacIop(channels[chnId].tadr + 4));

            channels[chnId].tadr += 8;
        }

        channels[chnId].madr = @truncate(u24, tag);
        channels[chnId].bcr.count = @truncate(u16, tag >> 32);

        info("   [DMAC (IOP)] MADR = 0x{X:0>6}, WC = {}", .{channels[chnId].madr, channels[chnId].bcr.count});

        if ((channels[chnId].bcr.count & 3) != 0) {
            channels[chnId].bcr.count = (channels[chnId].bcr.count | 3) + 1;
        }
    } else {
        channels[chnId].bcr.count -= 1;
        
        const data = bus.readDmacIop(channels[chnId].madr);

        sif.writeSif0(data);

        channels[chnId].madr +%= 4;

        if (channels[chnId].bcr.count == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    }
}

/// Performs SIF1 DMA
fn doSif1() void {
    // NOTE: Code logic taken from DobieStation.
    // NOTE: SIF1 DMA uses destination chain mode.

    const chnId = @enumToInt(Channel.Sif1);

    assert(channels[chnId].chcr.tte);

    if (channels[chnId].bcr.count == 0) {
        // Read new tag
        info("   [DMAC (IOP)] Channel {} ({s}) transfer, Chain mode.", .{chnId, @tagName(Channel.Sif1)});

        const tag = @as(u128, sif.readSif1()) | (@as(u128, sif.readSif1()) << 32) | (@as(u128, sif.readSif1()) << 64) | (@as(u128, sif.readSif1()) << 96);

        channels[chnId].tagEnd = (tag & (1 << 31)) != 0 or (tag & (1 << 30)) != 0;

        info("   [DMAC (IOP)] Tag = 0x{X:0>32} (Tag end = {})", .{tag, channels[chnId].tagEnd});

        channels[chnId].madr = @truncate(u24, tag);
        channels[chnId].bcr.count = @truncate(u16, (tag >> 32) & ~@as(u32, 3));

        info("   [DMAC (IOP)] MADR = 0x{X:0>6}, WC = {}", .{channels[chnId].madr, channels[chnId].bcr.count});
    } else {
        channels[chnId].bcr.count -= 1;

        const data = sif.readSif1();

        // info("   [DMAC (IOP)] [0x{X:0>6}] = 0x{X:0>8}", .{channels[chnId].madr, data});

        bus.writeIopDmac(channels[chnId].madr, data);

        channels[chnId].madr +%= 4;

        if (channels[chnId].bcr.count == 0 and channels[chnId].tagEnd) {
            channels[chnId].chcr.str = false;

            transferEnd(chnId);
        }
    }
}
