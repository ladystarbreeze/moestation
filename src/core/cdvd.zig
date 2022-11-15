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
    DriveStat  = 0x1F40_200A,
    SDriveStat = 0x1F40_200B,
    DiscType   = 0x1F40_200F,
    SCmd       = 0x1F40_2016,
    SCmdStat   = 0x1F40_2017,
    SCmdData   = 0x1F40_2018,
};

/// N commands
const NCommand = enum(u8) {
    ReadCd  = 0x06,
    ReadDvd = 0x08,
};

/// S commands
const SCommand = enum(u8) {
    Subcommand        = 0x03,
    UpdateStickyFlags = 0x05,
    ReadRtc           = 0x08,
    ForbidDvd         = 0x15,
    OpenConfig        = 0x40,
    ReadConfig        = 0x41,
    CloseConfig       = 0x43,
};

/// S subcommands
const SSubcommand = enum(u8) {
    MechaconVersion = 0x00,
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
        var data: u8 = 8;

        data |= @as(u8, @bitCast(u1, self.rdy)) << 6;
        data |= @as(u8, @bitCast(u1, self.bsy)) << 7;

        return data;
    }
};

/// S command data
const SCmdData = struct {
    buf: [16]u8 = undefined,
    idx: u5     = 0,

    /// Writes an S command data byte
    pub fn write(self: *SCmdData, data: u8) void {
        if (self.idx < 16) {
            self.buf[self.idx] = data;

            self.idx += 1;
        } else {
            warn("[CDVD      ] S command data buffer is full.", .{});
        }
    }

    /// Returns a data byte
    pub fn read(self: *SCmdData) u8 {
        var data: u8 = undefined;

        if (self.idx < 16) {
            data = self.buf[self.idx];

            self.idx += 1;
        } else {
            warn("[CDVD      ] S command data buffer is empty.", .{});
        }

        return data;
    }

    /// "Clears" the data buffer
    pub fn clear(self: *SCmdData) void {
        self.idx = 0;
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

//var driveStat: DriveStat = DriveStat{};
//var  nCmdStat: NCmdStat  = NCmdStat{};
var nCmdParam: NCmdParam = NCmdParam{};
var  sCmdStat: SCmdStat  = SCmdStat{};
var  sCmdData: SCmdData  = SCmdData{};

var  driveStat: u8 = 0;
var sDriveStat: u8 = 0;
var   nCmdStat: u8 = 0x40;
var      iStat: u8 = 0;

var  sectorNum: u32 = 0;

var sCmdParam: u8 = undefined;

var cyclesToRead: i32 = 0;
var cyclesToSeek: i32 = 0;

/// CDVD read buffer
var readBuf: ReadBuffer = ReadBuffer{};

/// ISO image
var cdvdFile: File = undefined;

/// Initializes the CDVD module
pub fn init(cdvdPath: []const u8) !void {
    //sDriveStat = driveStat.get();

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
            //info("   [CDVD      ] Read @ 0x{X:0>8} (N Command Status).", .{addr});

            data = nCmdStat;
        },
        @enumToInt(CdvdReg.CdvdError) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (CDVD Error).", .{addr});

            data = 0;
        },
        @enumToInt(CdvdReg.IStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (CDVD I_STAT).", .{addr});

            data = iStat;
        },
        @enumToInt(CdvdReg.DriveStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (Drive Status).", .{addr});

            data = driveStat;
        },
        @enumToInt(CdvdReg.SDriveStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (Sticky Drive Status).", .{addr});

            data = sDriveStat;
        },
        @enumToInt(CdvdReg.DiscType) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (Disc Type).", .{addr});

            data = @enumToInt(DiscType.Ps2Dvd);
        },
        0x1F40_2013 => {
            // Not sure what this is, DobieStation returns 4 on reads from this register.
            info("   [CDVD      ] Read @ 0x{X:0>8} (Unknown).", .{addr});

            data = 4;
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

            if (sCmdData.idx < sCmdLen) {
                data = sCmdData.read();

                if (sCmdData.idx == sCmdLen) {
                    sCmdStat.noData = true;
                    
                    sCmdData.clear();
                }
            } else {
                data = 0;
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

    const readSize: u32 = if (nCmd == @enumToInt(NCommand.ReadCd)) seekParam.size else 2064;

    if (readBuf.idx < readSize) {
        data = @as(u32, readBuf.get()) | (@as(u32, readBuf.get()) << 8) | (@as(u32, readBuf.get()) << 16) | (@as(u32, readBuf.get()) << 24);

        if (readBuf.idx == readSize) {
            dmac.setRequest(Channel.Cdvd, false);

            sectorNum += 1;

            if (sectorNum == seekParam.num) {
                sectorNum = 0;

                sendInterrupt();
            } else {
                cyclesToSeek = 1;
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

            sCmdParam = data;
        },
        else => {
            err("  [CDVD      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>2}.", .{addr, data});

            assert(false);
        }
    }
}

/// Sets DRIVE_STAT
fn setDriveStat(data: u8) void {
    driveStat = data;

    sDriveStat |= driveStat;
}

/// Calls N command handler
fn runNCmd(cmd: u8) void {
    nCmd = cmd;

    nCmdStat = 0x80;

    switch (cmd) {
        @enumToInt(NCommand.ReadCd ) => cmdReadCd(),
        @enumToInt(NCommand.ReadDvd) => cmdReadDvd(),
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
        @enumToInt(SCommand.Subcommand) => {
            switch (sCmdParam) {
                @enumToInt(SSubcommand.MechaconVersion) => cmdMechaconVersion(),
                else => {
                    err("  [CDVD      ] Unhandled S subcommand 0x{X:0>2}.", .{sCmdParam});

                    assert(false);
                }
            }
        },
        @enumToInt(SCommand.UpdateStickyFlags) => cmdUpdateStickyFlags(),
        @enumToInt(SCommand.ReadRtc          ) => cmdReadRtc(),
        @enumToInt(SCommand.ForbidDvd        ) => cmdForbidDvd(),
        @enumToInt(SCommand.OpenConfig       ) => cmdOpenConfig(),
        @enumToInt(SCommand.ReadConfig       ) => cmdReadConfig(),
        @enumToInt(SCommand.CloseConfig      ) => cmdCloseConfig(),
        else => {
            err("  [CDVD      ] Unhandled S command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }

    sCmdData.clear();
}

/// Sends a CDVD interrupt
pub fn sendInterrupt() void {
    setDriveStat(0xA);

    nCmdStat = 0x40;

    iStat |= 3;

    intc.sendInterruptIop(IntSource.Cdvd);
}

/// Seeks to a CD/DVD sector
fn doSeek() void {
    info("   [CDVD      ] Seek. POS = {}, NUM = {}, SIZE = {}", .{seekParam.pos + sectorNum, seekParam.num, seekParam.size});

    nCmdStat = 0x40;

    cdvdFile.seekTo(seekParam.pos * seekParam.size) catch {
        err("   [CDVD      ] Unable to seek to sector.", .{});

        assert(false);
    };

    cyclesToSeek = if (nCmd == 6) 1000 else 90_000;

    setDriveStat(0x12);
}

/// Reads a CD sector
fn doReadCd() void {
    info("   [CDVD      ] Reading CD sector {}...", .{seekParam.pos + sectorNum});

    setDriveStat(0x06);

    cdvdFile.seekTo(seekParam.pos * seekParam.size + sectorNum * seekParam.size) catch {
        err("   [CDVD      ] Unable to seek to sector.", .{});

        assert(false);
    };

    if (cdvdFile.reader().read(readBuf.buf[0..seekParam.size])) |bytesRead| {
        if (bytesRead == seekParam.size) {
            err("  [CDVD      ] Read size mismatch.", .{});

            assert(false);
        }
    } else |e| switch (e) {
        else => {
            err("  [moestation] Unhandled error {}.", .{e});

            assert(false);
        }
    }
}

/// Reads a DVD sector
fn doReadDvd() void {
    info("   [CDVD      ] Reading DVD sector {}...", .{seekParam.pos + sectorNum});

    setDriveStat(0x06);

    cdvdFile.seekTo(seekParam.pos * seekParam.size + sectorNum * seekParam.size) catch {
        err("   [CDVD      ] Unable to seek to sector.", .{});

        assert(false);
    };

    if (cdvdFile.reader().read(readBuf.buf[12..2060])) |bytesRead| {
        assert(bytesRead == seekParam.size);
    } else |e| switch (e) {
        else => {
            err("  [moestation] Unhandled error {}.", .{e});

            assert(false);
        }
    }

    const layerSectorNum = seekParam.pos + sectorNum + 0x30000;

    readBuf.buf[0x0] = 0x20;
    readBuf.buf[0x1] = @truncate(u8, layerSectorNum >> 16);
    readBuf.buf[0x2] = @truncate(u8, layerSectorNum >> 8);
    readBuf.buf[0x3] = @truncate(u8, layerSectorNum);
    readBuf.buf[0x4] = 0;
    readBuf.buf[0x5] = 0;
    readBuf.buf[0x6] = 0;
    readBuf.buf[0x7] = 0;
    readBuf.buf[0x8] = 0;
    readBuf.buf[0x9] = 0;
    readBuf.buf[0xA] = 0;
    readBuf.buf[0xB] = 0;

    readBuf.buf[2060] = 0;
    readBuf.buf[2061] = 0;
    readBuf.buf[2062] = 0;
    readBuf.buf[2063] = 0;
}

/// OpenConfig
fn cmdCloseConfig() void {
    info("   [CDVD      ] CloseConfig", .{});

    sCmdLen = 0;
}

/// Forbid DVD
fn cmdForbidDvd() void {
    info("   [CDVD      ] ForbidDvd", .{});

    sCmdData.write(5);

    sCmdLen = 1;
}

/// MechaconVersion
fn cmdMechaconVersion() void {
    info("   [CDVD      ] MechaconVersion", .{});

    sCmdStat.noData = false;

    sCmdData.write(0x03);
    sCmdData.write(0x06);
    sCmdData.write(0x02);
    sCmdData.write(0x00);

    sCmdLen = 4;
}

/// OpenConfig
fn cmdOpenConfig() void {
    info("   [CDVD      ] OpenConfig", .{});

    sCmdLen = 0;
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

    doSeek();
}

/// ReadConfig
fn cmdReadConfig() void {
    info("   [CDVD      ] ReadConfig", .{});

    sCmdStat.noData = false;
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);

    sCmdLen = 4 * 4;
}

/// ReadDvd
fn cmdReadDvd() void {
    info("   [CDVD      ] ReadDvd", .{});

    seekParam.pos  = @as(u32, nCmdParam.buf[0]) | (@as(u32, nCmdParam.buf[1]) << 8) | (@as(u32, nCmdParam.buf[2]) << 16) | (@as(u32, nCmdParam.buf[3]) << 24);
    seekParam.num  = @as(u32, nCmdParam.buf[4]) | (@as(u32, nCmdParam.buf[5]) << 8) | (@as(u32, nCmdParam.buf[6]) << 16) | (@as(u32, nCmdParam.buf[7]) << 24);
    seekParam.size = 2048;

    doSeek();
}

/// ReadRtc
fn cmdReadRtc() void {
    info("   [CDVD      ] ReadRtc", .{});

    sCmdStat.noData = false;
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);

    sCmdLen = 8;
}

/// Update Sticky Flags
fn cmdUpdateStickyFlags() void {
    info("   [CDVD      ] UpdateStickyFlags", .{});

    sDriveStat = driveStat;

    sCmdData.write(0);

    sCmdLen = 1;
}

pub fn step() void {
    if (cyclesToRead > 0) {
        cyclesToRead -= 1;

        if (cyclesToRead == 0) {
            dmac.setRequest(Channel.Cdvd, true);
        }
    }

    if (cyclesToSeek > 0) {
        cyclesToSeek -= 1;

        if (cyclesToSeek == 0) {
            if (nCmd == 6) {
                doReadCd();
                
                // NOTE: This speeds up the boot process
                cyclesToRead = 150;
            } else {
                doReadDvd();
                
                cyclesToRead = 15_000;
            }
        }
    }
}
