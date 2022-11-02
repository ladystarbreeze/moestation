//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cdvd.zig - CDVD controller module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const File = std.fs.File;

const openFile = std.fs.cwd().openFile;
const OpenMode = std.fs.File.OpenMode;

const dmac = @import("dmac_iop.zig");

const Channel = dmac.Channel;

const intc = @import("intc.zig");

const IntSource = intc.IntSourceIop;

/// CDVD registers
const CdvdReg = enum(u32) {
    NCmd       = 0x1F40_2004,
    NCmdStat   = 0x1F40_2005,
    CdvdError  = 0x1F40_2006,
    IStat      = 0x1F40_2008,
    //DriveStat  = 0x1F40_200A,
    SDriveStat = 0x1F40_200B,
    DiscType   = 0x1F40_200F,
    SCmd       = 0x1F40_2016,
    SCmdStat   = 0x1F40_2017,
    SCmdData   = 0x1F40_2018,
};

/// N commands
const NCommand = enum(u8) {
    ReadCd = 0x06,
};

/// S commands
const SCommand = enum(u8) {
    UpdateStickyFlags = 0x05,
    OpenConfig        = 0x40,
    ReadConfig        = 0x41,
    CloseConfig       = 0x43,
};

/// Disc types
const DiscType = enum(u8) {
    Ps2Dvd = 0x14,
};

/// Drive status register
const DriveStat = struct {
    trayOpen: bool = false,
    spinning: bool = false,
    readStat: bool = false,
      paused: bool = true,
    seekStat: bool = false,
     errStat: bool = false,

    /// Returns the drive status
    pub fn get(self: DriveStat) u8 {
        var data: u8 = 0;

        data |= @as(u8, @bitCast(u1, self.trayOpen));
        data |= @as(u8, @bitCast(u1, self.spinning)) << 1;
        data |= @as(u8, @bitCast(u1, self.readStat)) << 2;
        data |= @as(u8, @bitCast(u1, self.paused  )) << 3;
        data |= @as(u8, @bitCast(u1, self.seekStat)) << 4;
        data |= @as(u8, @bitCast(u1, self.errStat )) << 5;

        return data;
    }
};

/// N command parameters
const NCmdParam = struct {
    buf: [11]u8 = undefined,
    idx: u4 = 0,

    /// Writes an N command parameter byte
    pub fn write(self: *NCmdParam, data: u8) void {
        if (self.idx < 11) {
            self.buf[self.idx] = data;

            self.idx += 1;
        } else {
            warn("[CDVD      ] N command parameter buffer is full.", .{});
        }
    }

    /// "Clears" the command buffer
    pub fn clear(self: *NCmdParam) void {
        self.idx = 0;
    }
};

/// N command status
const NCmdStat = struct {
    rdy: bool = true,
    bsy: bool = false,

    /// Returns N command status register
    pub fn get(self: NCmdStat) u8 {
        var data: u8 = 0xE;

        data |= @as(u8, @bitCast(u1, self.rdy)) << 6;
        data |= @as(u8, @bitCast(u1, self.bsy)) << 7;

        return data;
    }
};

/// S command status
const SCmdStat = struct {
    noData: bool = true,
      busy: bool = false,

    /// Returns S command status register
    pub fn get(self: SCmdStat) u8 {
        var data: u8 = 0;

        data |= @as(u8, @bitCast(u1, self.noData)) << 6;
        data |= @as(u8, @bitCast(u1, self.busy)) << 7;

        return data | 8;
    }
};

/// Seek parameters
const SeekParam = struct {
     pos: u32 = undefined,
     num: u32 = undefined,
    size: u12 = undefined,
};

/// Read buffer
const ReadBuffer = struct {
    buf: [2064]u8 = undefined,
    idx: u12      = 0,

    /// Returns a byte from the read buffer
    pub fn get(self: *ReadBuffer) u8 {
        const data = self.buf[self.idx];

        self.idx += 1;

        return data;
    }

    /// Clear the read buffer
    pub fn clear(self: *ReadBuffer) void {
        self.idx = 0;
    }
};

/// CDVD registers
var nCmd: u8 = undefined;
var sCmd: u8 = undefined;
var sCmdLen: u8 = undefined;

var seekParam: SeekParam = SeekParam{};

var driveStat: DriveStat = DriveStat{};
var  nCmdStat: NCmdStat  = NCmdStat{};
var nCmdParam: NCmdParam = NCmdParam{};
var  sCmdStat: SCmdStat  = SCmdStat{};

var sDriveStat: u8 = undefined;
var      iStat: u8 = 0;

var  sectorNum: u32 = 0;

/// CDVD read buffer
var readBuf: ReadBuffer = ReadBuffer{};

/// ISO image
var cdvdFile: File = undefined;

/// Initializes the CDVD module
pub fn init(cdvdPath: []const u8) !void {
    sDriveStat = driveStat.get();

    info("   [CDVD      ] Loading ISO {s}...", .{cdvdPath});

    // Open CDVD ISO
    cdvdFile = try openFile(cdvdPath, .{.mode = OpenMode.read_only});
}

/// Deinitializes the CDVD module
pub fn deinit() void {
    cdvdFile.close();
}

/// Returns a CDVD register
pub fn read(addr: u32) u8 {
    var data: u8 = undefined;

    switch (addr) {
        @enumToInt(CdvdReg.NCmd) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (N Command).", .{addr});

            data = nCmd;
        },
        @enumToInt(CdvdReg.NCmdStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (N Command Status).", .{addr});

            data = nCmdStat.get();
        },
        @enumToInt(CdvdReg.CdvdError) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (CDVD Error).", .{addr});

            data = 0;
        },
        @enumToInt(CdvdReg.IStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (CDVD I_STAT).", .{addr});

            data = iStat;
        },
        @enumToInt(CdvdReg.SDriveStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (Sticky Drive Status).", .{addr});

            data = sDriveStat;
        },
        @enumToInt(CdvdReg.DiscType) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (Disc Type).", .{addr});

            data = @enumToInt(DiscType.Ps2Dvd);
        },
        @enumToInt(CdvdReg.SCmd) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (S Command).", .{addr});

            data = sCmd;
        },
        @enumToInt(CdvdReg.SCmdStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (S Command Status).", .{addr});

            data = sCmdStat.get();
        },
        @enumToInt(CdvdReg.SCmdData) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (S Command Data).", .{addr});

            data = 0;

            sCmdLen -= 1;

            if (sCmdLen == 0) {
                sCmdStat.noData = true;
            }
        },
        else => {
            err("  [CDVD      ] Unhandled read @ 0x{X:0>8}.", .{addr});

            assert(false);
        }
    }

    return data;
}

/// Reads data from the read buffer (from IOP DMA)
pub fn readDmac() u32 {
    var data: u32 = undefined;

    if (readBuf.idx < 4 * 512) {
        data = @as(u32, readBuf.get()) | (@as(u32, readBuf.get()) << 8) | (@as(u32, readBuf.get()) << 16) | (@as(u32, readBuf.get()) << 24);

        if (readBuf.idx == 4 * 512) {
            if (sectorNum == seekParam.num) {
                dmac.setRequest(Channel.Cdvd, false);

                sectorNum = 0;
            } else {
                doSeek();
                doReadCd();
            }
            
            readBuf.clear();
        }
    }

    return data;
}

/// Writes data to a CDVD register
pub fn write(addr: u32, data: u8) void {
    switch (addr) {
        @enumToInt(CdvdReg.NCmd) => {
            info("   [CDVD      ] Write @ 0x{X:0>8} (N Command) = 0x{X:0>2}.", .{addr, data});

            runNCmd(data);
        },
        @enumToInt(CdvdReg.NCmdStat) => {
            info("   [CDVD      ] Write @ 0x{X:0>8} (N Command Parameter) = 0x{X:0>2}.", .{addr, data});

            nCmdParam.write(data);
        },
        @enumToInt(CdvdReg.CdvdError) => {
            info("   [CDVD      ] Write @ 0x{X:0>8} (CDVD Mode) = 0x{X:0>2}.", .{addr, data});
        },
        @enumToInt(CdvdReg.IStat) => {
            info("   [CDVD      ] Write @ 0x{X:0>8} (CDVD I_STAT) = 0x{X:0>2}.", .{addr, data});

            iStat &= ~data;
        },
        @enumToInt(CdvdReg.SCmd) => {
            info("   [CDVD      ] Write @ 0x{X:0>8} (S Command) = 0x{X:0>2}.", .{addr, data});

            runSCmd(data);
        },
        @enumToInt(CdvdReg.SCmdStat) => {
            info("   [CDVD      ] Write @ 0x{X:0>8} (S Command Parameter) = 0x{X:0>2}.", .{addr, data});
        },
        else => {
            err("  [CDVD      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>2}.", .{addr, data});

            assert(false);
        }
    }
}

/// Calls N command handler
fn runNCmd(cmd: u8) void {
    nCmd = cmd;

    switch (cmd) {
        @enumToInt(NCommand.ReadCd) => cmdReadCd(),
        else => {
            err("  [CDVD      ] Unhandled N command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }

    nCmdParam.clear();
}

/// Calls S command handler
fn runSCmd(cmd: u8) void {
    sCmd = cmd;

    switch (cmd) {
        @enumToInt(SCommand.UpdateStickyFlags) => cmdUpdateStickyFlags(),
        @enumToInt(SCommand.OpenConfig       ) => cmdOpenConfig(),
        @enumToInt(SCommand.ReadConfig       ) => cmdReadConfig(),
        @enumToInt(SCommand.CloseConfig      ) => cmdCloseConfig(),
        else => {
            err("  [CDVD      ] Unhandled S command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }
}

/// Sends a CDVD interrupt
pub fn sendInterrupt() void {
    //driveStat.readStat = false;
    driveStat.paused   = true;

    iStat |= 3;

    intc.sendInterruptIop(IntSource.Cdvd);
}

/// Seeks to a CD/DVD sector
fn doSeek() void {
    info("   [CDVD      ] Seek. POS = {}, NUM = {}, SIZE = {}", .{seekParam.pos, seekParam.num, seekParam.size});

    driveStat.spinning = true;

    cdvdFile.seekTo(seekParam.pos * seekParam.size + seekParam.size * sectorNum) catch {
        err("   [CDVD      ] Unable to seek to sector.", .{});

        assert(false);
    };

    sectorNum += 1;
}

/// Reads a CD sector
fn doReadCd() void {
    info("   [CDVD      ] Reading sector {}...", .{seekParam.pos});

    //driveStat.seekStat = false;
    driveStat.readStat = true;

    if (cdvdFile.reader().read(readBuf.buf[0..seekParam.size])) |bytesRead| {
        assert(bytesRead == seekParam.size);
    } else |e| switch (e) {
        else => {
            err("  [moestation] Unhandled error {}.", .{e});

            assert(false);
        }
    }

    dmac.setRequest(Channel.Cdvd, true);
}

/// OpenConfig
fn cmdCloseConfig() void {
    info("   [CDVD      ] CloseConfig", .{});
}

/// OpenConfig
fn cmdOpenConfig() void {
    info("   [CDVD      ] OpenConfig", .{});
}

/// ReadCd
fn cmdReadCd() void {
    info("   [CDVD      ] ReadCd", .{});

    seekParam.pos = @as(u32, nCmdParam.buf[0]) | (@as(u32, nCmdParam.buf[1]) << 8) | (@as(u32, nCmdParam.buf[2]) << 16) | (@as(u32, nCmdParam.buf[3]) << 24);
    seekParam.num = @as(u32, nCmdParam.buf[4]) | (@as(u32, nCmdParam.buf[5]) << 8) | (@as(u32, nCmdParam.buf[6]) << 16) | (@as(u32, nCmdParam.buf[7]) << 24);

    switch (nCmdParam.buf[10]) {
        0    => seekParam.size = 2048,
        1    => seekParam.size = 2328,
        2    => seekParam.size = 2340,
        else => {
            err("  [CDVD      ] Unhandled sector size {}.", .{nCmdParam.buf[10]});

            assert(false);
        },
    }

    driveStat.paused = false;

    doSeek();
    doReadCd();
}

/// ReadConfig
fn cmdReadConfig() void {
    info("   [CDVD      ] ReadConfig", .{});

    sCmdStat.noData = false;

    sCmdLen = 4 * 4;
}

/// Update Sticky Flags
fn cmdUpdateStickyFlags() void {
    info("   [CDVD      ] UpdateStickyFlags", .{});

    sDriveStat = driveStat.get();
}
