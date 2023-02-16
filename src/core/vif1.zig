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

const cpu = @import("cpu.zig");

const dmac = @import("dmac.zig");

const Channel = dmac.Channel;

const gif = @import("gif.zig");

const ActivePath = gif.ActivePath;

const gs = @import("gs.zig");

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
    Flushe   = 0x10,
    Flush    = 0x11,
    Flusha   = 0x13,
    Mscal    = 0x14,
    Mscnt    = 0x17,
    Stmask   = 0x20,
    Strow    = 0x30,
    Stcol    = 0x31,
    Mpg      = 0x4A,
    Direct   = 0x50,
    Directhl = 0x51,
    Unpack   = 0x60,
};

const VifState = enum {
    Mpg,
    Direct,
    Unpack,
    Idle,
};

const MpgInfo = struct {
        size: u9  = 0,
    loadAddr: u16 = 0,
};

const UnpackMode = enum(u4) {
    S32   = 0x0,
    S16   = 0x1,
    S8    = 0x2,
    V2_32 = 0x4,
    V2_16 = 0x5,
    V2_8  = 0x6,
    V3_32 = 0x8,
    V3_16 = 0x9,
    V3_8  = 0xA,
    V4_32 = 0xC,
    V4_16 = 0xD,
    V4_8  = 0xE,
    V4_5  = 0xF,
};

const UnpackInfo = struct {
    size: u8   = 0,
    addr: u16  = 0,
     usn: bool = false,
    mode: UnpackMode = UnpackMode.S32,
};

const VifFifo = LinearFifo(u32, LinearFifoBufferType{.Static = 64});

/// VIF1 FIFO
var vif1Fifo = VifFifo.init();

/// VIF1_STAT
var vif1Stat = VifStat{};

/// VIF1_ERR
var vif1Err = VifErr{};

/// VIF address registers
var vif1Ofst: u10 = 0;
var vif1Base: u10 = 0;
var vif1Tops: u10 = 0;

pub var vif1Top: u10 = 0;

/// Current VIFcode
var vifCode: u32  = undefined;
var hasCode: bool = false;

var isCmdDone = false;

var vifState = VifState.Idle;

/// MPG
var mpgInfo = MpgInfo{};

/// UNPACK
var unpackInfo = UnpackInfo{};

var p2Count: u16 = 0;

// Stall control
var isStall = false;
var isStop  = false;

/// Downloads data from GS VRAM
pub fn downloadGs() u128 {
    return gs.download();
}

/// Reads data from the VIF
pub fn read(addr: u32) u32 {
    var data: u32 = undefined;

    switch (addr) {
        @enumToInt(VifReg.VifStat) => {
            std.debug.print("[VIF1      ] Read @ 0x{X:0>8} (VIF1_STAT)\n", .{addr});

            cpu.dumpRegs();

            data = vif1Stat.get() | (@truncate(u32, vif1Fifo.readableLength() / 4) << 24);
        },
        else => {
            std.debug.print("[VIF1      ] Unhandled read @ 0x{X:0>8}\n", .{addr});

            @panic("Unhandled VIF1 read");
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

    if (vif1Fifo.readableLength() <= 60) {
        dmac.setRequest(Channel.Vif1, true);
    }

    return data;
}

/// Writes data to the VIF
pub fn write(addr: u32, data: u32) void {
    switch (addr) {
        @enumToInt(VifReg.VifStat) => {
            std.debug.print("[VIF1      ] Write @ 0x{X:0>8} (VIF1_STAT) = 0x{X:0>8}\n", .{addr, data});

            vif1Stat.set(data);
        },
        @enumToInt(VifReg.VifFbrst) => {
            std.debug.print("[VIF1      ] Write @ 0x{X:0>8} (VIF1_FBRST) = 0x{X:0>8}\n", .{addr, data});

            if ((data & 1) != 0) {
                std.debug.print("[VIF1      ] VIF1 reset\n", .{});

                hasCode = false;

                vif1Stat.vps = 0;

                vif1Fifo = VifFifo.init();

                dmac.setRequest(Channel.Vif1, true);
            }

            if ((data & (1 << 1)) != 0) {
                std.debug.print("[VIF1      ] Force break\n", .{});

                vif1Stat.vfs = true;

                updateStall();
            }
            
            if ((data & (1 << 2)) != 0) {
                std.debug.print("[VIF1      ] STOP\n", .{});
                
                vif1Stat.vss = true;
            }
            
            if ((data & (1 << 3)) != 0) {
                std.debug.print("[VIF1      ] Stall cancel\n", .{});
                
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
            std.debug.print("[VIF1      ] Write @ 0x{X:0>8} (VIF1_ERR) = 0x{X:0>8}\n", .{addr, data});

            vif1Err.set(data);
        },
        else => {
            std.debug.print("[VIF1      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}\n", .{addr, data});

            @panic("Unhandled VIF1 write");
        }
    }
}

/// Writes data to VIF1 FIFO
pub fn writeFifo(comptime T: type, data: T) void {
    assert(T == u128 or T == u64);

    std.debug.print("[VIF1      ] Write ({s}) @ FIFO = 0x{X:0>32}\n", .{@typeName(T), data});

    const cnt: u7 = if (T == u128) 4 else 2;

    var i: u7 = 0;
    while (i < cnt) : (i += 1) {
        vif1Fifo.writeItem(@truncate(u32, @as(u128, data) >> (32 * i))) catch {
            std.debug.print("[VIF1      ] VIF1 FIFO is full\n", .{});
            
            @panic("VIF FIFO is full");
        };
    }

    if (vif1Fifo.readableLength() > 60) {
        dmac.setRequest(Channel.Vif1, false);
    }
}

/// Update stall
fn updateStall() void {
    isStall = vif1Stat.vfs or isStop;

    std.debug.print("[VIF1      ] Stall = {}\n", .{isStall});
}

/// Returns true if PATH2 is active, requests PATH2 and returns false if not
pub fn isP2Active() bool {
    if (gif.isP2Active()) return true;
    
    gif.setActivePath(ActivePath.Path2);

    vif1Stat.vps = 3;

    return false;
}

/// Releases PATH2, returns VIF1 to idle state
pub fn releaseP2() void {
    std.debug.print("[VIF1      ] Release PATH2, return to idle state\n", .{});

    gif.pathEnd();

    vif1Stat.vps = 0;
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
        @enumToInt(VifCode.Flushe  ) => iFlushe(),
        @enumToInt(VifCode.Flush   ) => iFlush(),
        @enumToInt(VifCode.Flusha  ) => iFlusha(),
        @enumToInt(VifCode.Mscal   ) => iMscal(vifCode),
        @enumToInt(VifCode.Mscnt   ) => iMscnt(),
        @enumToInt(VifCode.Stmask  ) => iStmask(),
        @enumToInt(VifCode.Strow   ) => iStrow(),
        @enumToInt(VifCode.Stcol   ) => iStcol(),
        @enumToInt(VifCode.Mpg     ) => iMpg(vifCode),
        @enumToInt(VifCode.Direct  ) => iDirect(vifCode),
        @enumToInt(VifCode.Directhl) => iDirecthl(vifCode),
        @enumToInt(VifCode.Unpack  ) ... @enumToInt(VifCode.Unpack) + 0x1F => iUnpack(vifCode),
        else => {
            std.debug.print("[VIF1      ] Unhandled VIFcode 0x{X:0>2} (0x{X:0>8})\n", .{cmd, vifCode});

            @panic("Unhandled VIFcode");
        }
    }

    if (isCmdDone) {
        cmdDone();
    }
}

/// Terminates a VIF command
fn cmdDone() void {
    std.debug.print("[VIF1      ] Command finished, returning to idle state\n", .{});

    hasCode = false;

    vif1Stat.vps = 0;

    if ((vifCode & (1 << 31)) != 0) {
        std.debug.print("[VIF1      ] Unhandled VIFcode interrupt\n", .{});

        @panic("Unhandled VIFcode interrupt");
    }

    if (vif1Stat.vss) {
        isStop = true;

        updateStall();
    }

    isCmdDone = false;

    vifState = VifState.Idle;
}

/// BASE
fn iBase(code: u32) void {
    vif1Base = @truncate(u10, code);

    std.debug.print("[VIF1      ] BASE; BASE = 0x{X:0>3}\n", .{vif1Base});

    isCmdDone = true;
}

/// send data to gif DIRECTly? :)
fn iDirect(code: u32) void {
    p2Count = @truncate(u16, code);

    std.debug.print("[VIF1      ] DIRECT; SIZE = {}\n", .{p2Count});

    vifState = VifState.Direct;
}

/// DIRECTHL
fn iDirecthl(code: u32) void {
    p2Count = @truncate(u16, code);

    // TODO: check for ongoing PATH3 transfer

    std.debug.print("[VIF1      ] DIRECTHL; SIZE = {}\n", .{p2Count});

    vifState = VifState.Direct;
}

/// FLUSH
fn iFlush() void {
    if (!cpu.vu[1].isIdle() or gif.isP1Active() or gif.isP2Active()) return;

    std.debug.print("[VIF1      ] FLUSH\n", .{});

    isCmdDone = true;
}

/// FLUSHA
fn iFlusha() void {
    if (!cpu.vu[1].isIdle() or gif.isP1Active() or gif.isP2Active() or gif.isP3Pending()) return;

    std.debug.print("[VIF1      ] FLUSHA\n", .{});

    isCmdDone = true;
}

/// FLUSHE
fn iFlushe() void {
    if (!cpu.vu[1].isIdle()) return;

    std.debug.print("[VIF1      ] FLUSHE\n", .{});

    isCmdDone = true;
}

/// ITOP
fn iItop(code: u32) void {
    const addr = @truncate(u10, code);

    std.debug.print("[VIF1      ] ITOP; ADDR = 0x{X:0>3}\n", .{addr});

    isCmdDone = true;
}

/// MARK
fn iMark(code: u32) void {
    const mark = @truncate(u16, code);

    std.debug.print("[VIF1      ] MARK; MARK = 0x{X:0>4}\n", .{mark});

    isCmdDone = true;
}

/// upload MicroProGram
fn iMpg(code: u32) void {
    mpgInfo.size     = @as(u9, @truncate(u8, code >> 16)) << 1;
    mpgInfo.loadAddr = @truncate(u16, code) << 3;

    std.debug.print("[VIF1      ] MPG; SIZE = {}, LOADADDR = 0x{X:0>4}\n", .{mpgInfo.size >> 1, mpgInfo.loadAddr});

    vifState = VifState.Mpg;
}

/// MicroSubroutine CALl
fn iMscal(code: u32) void {
    if (!cpu.vu[1].isIdle()) return;

    const execAddr = @truncate(u16, code) << 3;

    std.debug.print("[VIF1      ] MSCAL; EXECADDR = 0x{X:0>4}\n", .{execAddr});

    cpu.vu[1].startMicro(execAddr);

    vif1Top = vif1Tops;

    vif1Tops = if (vif1Stat.dbf) vif1Base else vif1Base + vif1Ofst;

    vif1Stat.dbf = !vif1Stat.dbf;

    isCmdDone = true;
}

/// MicroSubroutine CoNTinue
fn iMscnt() void {
    if (!cpu.vu[1].isIdle()) return;

    std.debug.print("[VIF1      ] MSCNT\n", .{});

    cpu.vu[1].continueMicro();

    vif1Top = vif1Tops;

    vif1Tops = if (vif1Stat.dbf) vif1Base else vif1Base + vif1Ofst;

    vif1Stat.dbf = !vif1Stat.dbf;

    isCmdDone = true;
}

/// MaSK PATH3
fn iMskpath3(code: u32) void {
    const mask = (code & (1 << 15)) != 0;

    std.debug.print("[VIF1      ] MSKPATH3; MASK = {}\n", .{mask});

    isCmdDone = true;
}

/// NO oPeration
fn iNop() void {
    std.debug.print("[VIF1      ] NOP\n", .{});

    isCmdDone = true;
}

/// OFFSET
fn iOffset(code: u32) void {
    vif1Ofst = @truncate(u10, code);

    std.debug.print("[VIF1      ] OFFSET; OFFSET = 0x{X:0>3}\n", .{vif1Ofst});

    vif1Tops = vif1Base;

    vif1Stat.dbf = false;

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

    std.debug.print("[VIF1      ] STCOL; COL = 0x{X:0>8}{X:0>8}{X:0>8}{X:0>8}\n", .{c3, c2, c1, c0});

    isCmdDone = true;
}

/// SeT CYCLe
fn iStcycl(code: u32) void {
    const cl = @truncate(u8, code);
    const wl = @truncate(u8, code >> 8);

    std.debug.print("[VIF1      ] STCYCL; CL = 0x{X:0>2}, WL = 0x{X:0>2}\n", .{cl, wl});

    if (cl != wl) {
        std.debug.print("[VIF1      ] Unhandled CL/WL setting\n", .{});

        @panic("Unhandled VIF CYCLE setting");
    }

    isCmdDone = true;
}

/// SeT MASK
fn iStmask() void {
    if (vif1Fifo.readableLength() == 0) {
        vif1Stat.vps = 1;

        return;
    }

    const mask = readFifo(u32);

    std.debug.print("[VIF1      ] STMASK; MASK = 0x{X:0>8}\n", .{mask});

    if (mask != 0) {
        std.debug.print("[VIF1      ] Write mask is not 0\n", .{});

        @panic("Write mask is not 0");
    }

    isCmdDone = true;
}

/// SeT MODe
fn iStmod(code: u32) void {
    const mode = @truncate(u2, code);

    std.debug.print("[VIF1      ] STMOD; MODE = 0b{b:0>2}\n", .{mode});

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

    std.debug.print("[VIF1      ] STROW; ROW = 0x{X:0>8}{X:0>8}{X:0>8}{X:0>8}\n", .{r3, r2, r1, r0});

    isCmdDone = true;
}

/// UNPACK
fn iUnpack(code: u32) void {
    unpackInfo.size = @truncate(u8, code >> 16);
    unpackInfo.addr = @as(u16, @truncate(u9, code)) << 4;
    unpackInfo.usn  = (code & (1 << 14)) != 0;

    unpackInfo.mode = @intToEnum(UnpackMode, @truncate(u4, code >> 24));

    std.debug.print("[VIF1      ] UNPACK ({s}); SIZE = {}, ADDR = 0x{X:0>4}, USN = {}\n", .{@tagName(unpackInfo.mode), unpackInfo.size, unpackInfo.addr, unpackInfo.usn});

    if ((code & (1 << 15)) != 0) {
        unpackInfo.addr += @as(u16, vif1Tops) << 4;
    }

    vifState = VifState.Unpack;
}

/// Steps VIF1
pub fn step() void {
    if (vif1Stat.fdr or isStall or vif1Fifo.readableLength() == 0) {
        return;
    }

    switch (vifState) {
        VifState.Mpg => {
            const data = readFifo(u32);

            std.debug.print("[VIF1      ] VU1 MPG write @ 0x{X:0>4} = 0x{X:0>8}\n", .{mpgInfo.loadAddr, data});

            cpu.vu[1].writeCode(u32, mpgInfo.loadAddr, data);

            mpgInfo.loadAddr += 4;

            mpgInfo.size -%= 1;
            
            if (mpgInfo.size == 0) cmdDone();
        },
        VifState.Direct => {
            if (vif1Fifo.readableLength() < 4) return;

            if (!isP2Active()) return;

            gif.writePath2(@as(u128, readFifo(u32)) | (@as(u128, readFifo(u32)) << 32) | (@as(u128, readFifo(u32)) << 64) | (@as(u128, readFifo(u32)) << 96));

            p2Count -%= 1;
            
            if (p2Count == 0) {
                cmdDone();

                releaseP2();
            }
        },
        VifState.Unpack => {
            switch (unpackInfo.mode) {
                UnpackMode.V4_32 => {
                    if (vif1Fifo.readableLength() < 4) return;

                    const data = @as(u128, readFifo(u32)) | (@as(u128, readFifo(u32)) << 32) | (@as(u128, readFifo(u32)) << 64) | (@as(u128, readFifo(u32)) << 96);

                    cpu.vu[1].writeData(u128, unpackInfo.addr, data);

                    unpackInfo.addr += @sizeOf(u128);
                },
                UnpackMode.V4_8 => {
                    if (vif1Fifo.readableLength() == 0) return;

                    const data = readFifo(u32);

                    var unpackData: u128 = 0;

                    if (unpackInfo.usn) {
                        unpackData |= @as(u128, @truncate(u8, data));
                        unpackData |= @as(u128, @truncate(u8, data >>  8)) << 32;
                        unpackData |= @as(u128, @truncate(u8, data >> 16)) << 64;
                        unpackData |= @as(u128, @truncate(u8, data >> 24)) << 96;
                    } else {
                        unpackData |= @as(u128, @bitCast(u32, @as(i32, @bitCast(i8, @truncate(u8, data)))));
                        unpackData |= @as(u128, @bitCast(u32, @as(i32, @bitCast(i8, @truncate(u8, data >>  8))))) << 32;
                        unpackData |= @as(u128, @bitCast(u32, @as(i32, @bitCast(i8, @truncate(u8, data >> 16))))) << 64;
                        unpackData |= @as(u128, @bitCast(u32, @as(i32, @bitCast(i8, @truncate(u8, data >> 24))))) << 96;
                    }

                    cpu.vu[1].writeData(u128, unpackInfo.addr, unpackData);

                    unpackInfo.addr += @sizeOf(u128);
                },
                else => {
                    std.debug.print("Unhandled UNPACK\n", .{});

                    @panic("Unhandled UNPACK");
                }
            }

            unpackInfo.size -%= 1;
                    
            if (unpackInfo.size == 0) cmdDone();
        },
        VifState.Idle => {
            if (!hasCode) {
                vifCode = readFifo(u32);

                hasCode = true;
            }

            doCmd();
        }
    }
}
