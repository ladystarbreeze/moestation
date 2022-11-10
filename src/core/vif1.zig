//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! vif1.zig - Vector Interface 1
//!

const std = @import("std");

const assert = std.debug.assert;

const LinearFifo = std.fifo.LinearFifo;
const LinearFifoBufferType = std.fifo.LinearFifoBufferType;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const dmac = @import("dmac.zig");

const Channel = dmac.Channel;

/// VIF registers
const VifReg = enum(u32) {
    VifStat  = 0x1000_3C00,
    VifFbrst = 0x1000_3C10,
    VifErr   = 0x1000_3C20,
    VifMark  = 0x1000_3C30,
    VifCycle = 0x1000_3C40,
    VifMode  = 0x1000_3C50,
    VifNum   = 0x1000_3C60,
    VifMask  = 0x1000_3C70,
    VifCode  = 0x1000_3C80,
    VifItops = 0x1000_3C90,
    Vif1Base = 0x1000_3CA0,
    Vif1Ofst = 0x1000_3CB0,
    Vif1Tops = 0x1000_3CC0,
    VifItop  = 0x1000_3CD0,
    VifRn    = 0x1000_3D00,
    VifCn    = 0x1000_3D40,
};

/// VIF_ERR
const VifErr = struct {
    mi1: bool = false, // Mask Interrupt
    me0: bool = false, // Mask Error 0
    me1: bool = false, // Mask Error 1

    /// Sets VIF_ERR
    pub fn set(self: *VifErr, data: u32) void {
        self.mi1 = (data & 1) != 0;
        self.me0 = (data & (1 << 1)) != 0;
        self.me1 = (data & (1 << 2)) != 0;
    }
};

/// VIF_STAT
const VifStat = struct {
    vps: u2   = 0,     // VIF Packet Status
    vew: bool = false, // VIF Execute Wait
    vgw: bool = false, // VIF GIF Wait
    mrk: bool = false, // MARK
    dbf: bool = false, // Double Buffer Flag
    vss: bool = false, // VIF STOP Stall
    vfs: bool = false, // VIF Force break Stall
    vis: bool = false, // VIF Interrupt Stall
    int: bool = false, // INTerrupt
    er0: bool = false, // DMAtag mismatch ERror
    er1: bool = false, // Invalid VIF command
    fdr: bool = false, // FIFO DiRection

    /// Returns VIF_STAT
    pub fn get(self: VifStat) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.vps);
        data |= @as(u32, @bitCast(u1, self.vew)) << 2;
        data |= @as(u32, @bitCast(u1, self.vgw)) << 3;
        data |= @as(u32, @bitCast(u1, self.mrk)) << 6;
        data |= @as(u32, @bitCast(u1, self.dbf)) << 7;
        data |= @as(u32, @bitCast(u1, self.vss)) << 8;
        data |= @as(u32, @bitCast(u1, self.vfs)) << 9;
        data |= @as(u32, @bitCast(u1, self.vis)) << 10;
        data |= @as(u32, @bitCast(u1, self.int)) << 11;
        data |= @as(u32, @bitCast(u1, self.er0)) << 12;
        data |= @as(u32, @bitCast(u1, self.er1)) << 13;
        data |= @as(u32, @bitCast(u1, self.fdr)) << 23;

        return data;
    }

    /// Sets VIF_STAT
    pub fn set(self: *VifStat, data: u32) void {
        self.fdr = (data & (1 << 23)) != 0;
    }
};

/// VIFcodes
const VifCode = enum(u7) {
    Nop      = 0x00,
    Stcycl   = 0x01,
    Offset   = 0x02,
    Base     = 0x03,
    Itop     = 0x04,
    Stmod    = 0x05,
    Mskpath3 = 0x06,
    Mark     = 0x07,
    Stmask   = 0x20,
    Strow    = 0x30,
    Stcol    = 0x31,
};

const VifFifo = LinearFifo(u32, LinearFifoBufferType{.Static = 64});

/// VIF1 FIFO
var vif1Fifo = VifFifo.init();

/// VIF1_STAT
var vif1Stat = VifStat{};

/// VIF1_ERR
var vif1Err = VifErr{};

/// Current VIFcode
var vifCode: u32  = undefined;
var hasCode: bool = false;

var isCmdDone = false;

// Stall control
var isStall = false;
var isStop  = false;

/// Reads data from the VIF
pub fn read(addr: u32) u32 {
    var data: u32 = undefined;

    switch (addr) {
        @enumToInt(VifReg.VifStat) => {
            info("   [VIF1      ] Read @ 0x{X:0>8} (VIF1_STAT).", .{addr});

            data = vif1Stat.get() | (@truncate(u32, vif1Fifo.readableLength()) << 24);
        },
        else => {
            err("  [VIF1      ] Unhandled read @ 0x{X:0>8}.", .{addr});

            assert(false);
        }
    }

    return data;
}

/// Reads data from VIF1 FIFO
pub fn readFifo(comptime T: type) T {
    assert(T == u32 or T == u64);

    var data: T = undefined;
    
    if (T == u64) {
        data = @as(u64, vif1Fifo.readItem().?) | (@as(u64, vif1Fifo.readItem().?) << 32);
    } else {
        data = vif1Fifo.readItem().?;
    }

    if (vif1Fifo.readableLength() != 64) {
        dmac.setRequest(Channel.Vif1, true);
    }

    return data;
}

/// Writes data to the VIF
pub fn write(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(VifReg.VifStat) => {
            info("   [VIF1      ] Write @ 0x{X:0>8} (VIF1_STAT) = 0x{X:0>8}.", .{addr, data});

            vif1Stat.set(data);
        },
        @enumToInt(VifReg.VifFbrst) => {
            info("   [VIF1      ] Write @ 0x{X:0>8} (VIF1_FBRST) = 0x{X:0>8}.", .{addr, data});

            if ((data & 1) != 0) {
                info("   [VIF1      ] VIF1 reset.", .{});

                hasCode = false;

                vif1Stat.vps = 0;

                vif1Fifo = VifFifo.init();

                dmac.setRequest(Channel.Vif1, false);
            }

            if ((data & (1 << 1)) != 0) {
                info("   [VIF1      ] Force break.", .{});

                vif1Stat.vfs = true;

                updateStall();
            }
            
            if ((data & (1 << 2)) != 0) {
                info("   [VIF1      ] STOP.", .{});
                
                vif1Stat.vss = true;
            }
            
            if ((data & (1 << 3)) != 0) {
                info("   [VIF1      ] Stall cancel.", .{});
                
                vif1Stat.vss = false;
                vif1Stat.vfs = false;
                vif1Stat.vis = false;
                vif1Stat.int = false;
                vif1Stat.er0 = false;
                vif1Stat.er1 = false;

                updateStall();
            }
        },
        @enumToInt(VifReg.VifErr) => {
            info("   [VIF1      ] Write @ 0x{X:0>8} (VIF1_ERR) = 0x{X:0>8}.", .{addr, data});

            vif1Err.set(data);
        },
        else => {
            err("  [VIF1      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

            assert(false);
        }
    }
}

/// Writes data to VIF1 FIFO
pub fn writeFifo(data: u128) void {
    info("   [VIF1      ] Write @ FIFO = 0x{X:0>32}.", .{data});

    var i: u7 = 0;
    while (i < 4) : (i += 1) {
        vif1Fifo.writeItem(@truncate(u32, data >> (32 * i))) catch {
            err("  [VIF1      ] VIF1 FIFO is full.", .{});
            
            assert(false);
        };
    }

    if (vif1Fifo.readableLength() == 64) {
        dmac.setRequest(Channel.Vif1, false);
    }
}

/// Update stall
fn updateStall() void {
    isStall = vif1Stat.vfs or isStop;
}

/// Executes a VIFcode
fn doCmd() void {
    const cmd = @truncate(u7, vifCode >> 24);

    switch (cmd) {
        @enumToInt(VifCode.Nop     ) => iNop(),
        @enumToInt(VifCode.Stcycl  ) => iStcycl(vifCode),
        @enumToInt(VifCode.Offset  ) => iOffset(vifCode),
        @enumToInt(VifCode.Base    ) => iBase(vifCode),
        @enumToInt(VifCode.Itop    ) => iItop(vifCode),
        @enumToInt(VifCode.Stmod   ) => iStmod(vifCode),
        @enumToInt(VifCode.Mskpath3) => iMskpath3(vifCode),
        @enumToInt(VifCode.Mark    ) => iMark(vifCode),
        @enumToInt(VifCode.Stmask  ) => iStmask(),
        @enumToInt(VifCode.Strow   ) => iStrow(),
        @enumToInt(VifCode.Stcol   ) => iStcol(),
        else => {
            err("  [VIF1      ] Unhandled VIFcode 0x{X:0>2} (0x{X:0>8}).", .{cmd, vifCode});

            assert(false);
        }
    }

    if (!isCmdDone) {
        return;
    }

    hasCode = false;

    vif1Stat.vps = 0;

    if ((vifCode & (1 << 31)) != 0) {
        err("  [VIF1      ] Unhandled VIFcode interrupt.", .{});

        assert(false);
    }

    if (vif1Stat.vss) {
        isStop = true;

        updateStall();
    }
}

/// BASE
fn iBase(code: u32) void {
    const base = @truncate(u10, code);

    info("   [VIF1      ] BASE; BASE = 0x{X:0>3}", .{base});

    isCmdDone = true;
}

/// ITOP
fn iItop(code: u32) void {
    const addr = @truncate(u10, code);

    info("   [VIF1      ] ITOP; ADDR = 0x{X:0>3}", .{addr});

    isCmdDone = true;
}

/// MARK
fn iMark(code: u32) void {
    const mark = @truncate(u16, code);

    info("   [VIF1      ] MARK; MARK = 0x{X:0>4}", .{mark});

    isCmdDone = true;
}

/// MaSK PATH3
fn iMskpath3(code: u32) void {
    const mask = (code & (1 << 15)) != 0;

    info("   [VIF1      ] MSKPATH3; MASK = {}", .{mask});

    isCmdDone = true;
}

/// NO oPeration
fn iNop() void {
    info("   [VIF1      ] NOP", .{});

    isCmdDone = true;
}

/// OFFSET
fn iOffset(code: u32) void {
    const offset = @truncate(u10, code);

    info("   [VIF1      ] OFFSET; OFFSET = 0x{X:0>3}", .{offset});

    isCmdDone = true;
}

/// SeT COLumn
fn iStcol() void {
    if (vif1Fifo.readableLength() < 4) {
        vif1Stat.vps = 1;

        return;
    }

    const c0 = readFifo(u32);
    const c1 = readFifo(u32);
    const c2 = readFifo(u32);
    const c3 = readFifo(u32);

    info("   [VIF1      ] STCOL; COL = 0x{X:0>8}{X:0>8}{X:0>8}{X:0>8}", .{c3, c2, c1, c0});

    isCmdDone = true;
}

/// SeT CYCLe
fn iStcycl(code: u32) void {
    const cl = @truncate(u8, code);
    const wl = @truncate(u8, code >> 8);

    info("   [VIF1      ] STCYCL; CL = 0x{X:0>2}, WL = 0x{X:0>2}", .{cl, wl});

    isCmdDone = true;
}

/// SeT MASK
fn iStmask() void {
    if (vif1Fifo.readableLength() == 0) {
        vif1Stat.vps = 1;

        return;
    }

    const mask = readFifo(u32);

    info("   [VIF1      ] STMASK; MASK = 0x{X:0>8}", .{mask});

    isCmdDone = true;
}

/// SeT MODe
fn iStmod(code: u32) void {
    const mode = @truncate(u2, code);

    info("   [VIF1      ] STMOD; MODE = 0b{b:0>2}", .{mode});

    isCmdDone = true;
}

/// SeT ROW
fn iStrow() void {
    if (vif1Fifo.readableLength() < 4) {
        vif1Stat.vps = 1;

        return;
    }

    const r0 = readFifo(u32);
    const r1 = readFifo(u32);
    const r2 = readFifo(u32);
    const r3 = readFifo(u32);

    info("   [VIF1      ] STROW; ROW = 0x{X:0>8}{X:0>8}{X:0>8}{X:0>8}", .{r3, r2, r1, r0});

    isCmdDone = true;
}

/// Steps VIF1
pub fn step() void {
    if (isStall or vif1Fifo.readableLength() == 0) {
        return;
    }

    if (!hasCode) {
        vifCode = readFifo(u32);
    }

    doCmd();
}
