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

//const iopClock: i64 = 36_864_000;
const iopClock: i64 = 368_640; // Speed hack

const  readSpeedCd: i64 = 24 * 153_600;
const readSpeedDvd: i64 =  4 * 1_382_400;

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
    Nop     = 0x00,
    Pause   = 0x04,
    ReadCd  = 0x06,
    ReadDvd = 0x08,
    GetToc  = 0x09,
};

/// S commands
const SCommand = enum(u8) {
    Subcommand        = 0x03,
    UpdateStickyFlags = 0x05,
    ReadRtc           = 0x08,
    ForbidDvd         = 0x15,
    ReadILinkModel    = 0x17,
    BootCertify       = 0x1A,
    CancelPwOffReady  = 0x1B,
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
var nCmd: u8 = 0;
var sCmd: u8 = 0;
var sCmdLen: u8 = 0;

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

var    sectorNum: u32 = 0;
var oldSectorNum: u32 = 0;

var sCmdParam: u8 = undefined;

var cyclesToRead: i64 = -1;
var cyclesToSeek: i64 = -1;

/// CDVD read buffer
var readBuf: ReadBuffer = ReadBuffer{};

/// ISO image
var cdvdFile: File = undefined;

/// Initializes the CDVD module
pub fn init(cdvdPath: []const u8) !void {
    //sDriveStat = driveStat.get();

    std.debug.print("[CDVD      ] Loading ISO {s}...\n", .{cdvdPath});

    // Open CDVD ISO
    cdvdFile = try openFile(cdvdPath, .{.mode = OpenMode.read_only});

    // Paused
    setDriveStat(8);
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
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (N Command)\n", .{addr});

            data = nCmd;
        },
        @enumToInt(CdvdReg.NCmdStat) => {
            //std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (N Command Status)\n", .{addr});

            data = nCmdStat;
        },
        @enumToInt(CdvdReg.CdvdError) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (CDVD Error)\n", .{addr});

            data = 0;
        },
        @enumToInt(CdvdReg.IStat) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (CDVD I_STAT)\n", .{addr});

            data = iStat;
        },
        @enumToInt(CdvdReg.DriveStat) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (Drive Status)\n", .{addr});

            data = driveStat;
        },
        @enumToInt(CdvdReg.SDriveStat) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (Sticky Drive Status)\n", .{addr});

            data = sDriveStat;
        },
        @enumToInt(CdvdReg.DiscType) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (Disc Type)\n", .{addr});

            data = @enumToInt(DiscType.Ps2Dvd);
        },
        0x1F40_2013 => {
            // Not sure what this is, DobieStation returns 4 on reads from this register.
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (Unknown)\n", .{addr});

            data = 4;
        },
        @enumToInt(CdvdReg.SCmd) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (S Command)\n", .{addr});

            data = sCmd;
        },
        @enumToInt(CdvdReg.SCmdStat) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (S Command Status)\n", .{addr});

            data = sCmdStat.get();
        },
        @enumToInt(CdvdReg.SCmdData) => {
            std.debug.print("[CDVD      ] Read @ 0x{X:0>8} (S Command Data)\n", .{addr});

            if (sCmdData.idx < sCmdLen) {
                data = sCmdData.read();

                if (sCmdData.idx == sCmdLen) {
                    sCmdStat.noData = true;
                    sCmdStat.busy   = false;
                    
                    sCmdData.clear();
                }
            } else {
                data = 0;
            }
        },
        else => {
            std.debug.print("[CDVD      ] Unhandled read @ 0x{X:0>8}\n", .{addr});

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

            oldSectorNum = seekParam.pos + sectorNum;

            //std.debug.print("Reading sector {}...\n", .{seekParam.pos + sectorNum});

            sectorNum += 1;

            if (sectorNum == seekParam.num) {
                sectorNum = 0;

                sendInterrupt();
            } else {
                cyclesToSeek = 0;
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
            std.debug.print("[CDVD      ] Write @ 0x{X:0>8} (N Command) = 0x{X:0>2}\n", .{addr, data});

            runNCmd(data);
        },
        @enumToInt(CdvdReg.NCmdStat) => {
            std.debug.print("[CDVD      ] Write @ 0x{X:0>8} (N Command Parameter) = 0x{X:0>2}\n", .{addr, data});

            nCmdParam.write(data);
        },
        @enumToInt(CdvdReg.CdvdError) => {
            std.debug.print("[CDVD      ] Write @ 0x{X:0>8} (CDVD Mode) = 0x{X:0>2}\n", .{addr, data});
        },
        @enumToInt(CdvdReg.IStat) => {
            std.debug.print("[CDVD      ] Write @ 0x{X:0>8} (CDVD I_STAT) = 0x{X:0>2}\n", .{addr, data});

            iStat &= ~data;
        },
        @enumToInt(CdvdReg.SCmd) => {
            std.debug.print("[CDVD      ] Write @ 0x{X:0>8} (S Command) = 0x{X:0>2}\n", .{addr, data});

            runSCmd(data);
        },
        @enumToInt(CdvdReg.SCmdStat) => {
            std.debug.print("[CDVD      ] Write @ 0x{X:0>8} (S Command Parameter) = 0x{X:0>2}\n", .{addr, data});

            sCmdParam = data;
        },
        else => {
            std.debug.print("[CDVD      ] Unhandled write @ 0x{X:0>8} = 0x{X:0>2}\n", .{addr, data});

            assert(false);
        }
    }
}

/// Get block timing
fn getBlockTiming(isDvd: bool) i64 {
    return @divTrunc(iopClock * seekParam.size, if (isDvd) readSpeedDvd else readSpeedCd);
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
        @enumToInt(NCommand.Nop    ) => cmdNop(),
        @enumToInt(NCommand.Pause  ) => cmdPause(),
        @enumToInt(NCommand.ReadCd ) => cmdReadCd(),
        @enumToInt(NCommand.ReadDvd) => cmdReadDvd(),
        @enumToInt(NCommand.GetToc ) => cmdGetToc(),
        else => {
            std.debug.print("[CDVD      ] Unhandled N command 0x{X:0>2}.", .{cmd});

            @panic("Unhandled CDVD command");
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
                    std.debug.print("[CDVD      ] Unhandled S subcommand 0x{X:0>2}.", .{sCmdParam});

                    assert(false);
                }
            }
        },
        @enumToInt(SCommand.UpdateStickyFlags) => cmdUpdateStickyFlags(),
        @enumToInt(SCommand.ReadRtc          ) => cmdReadRtc(),
        @enumToInt(SCommand.ForbidDvd        ) => cmdForbidDvd(),
        @enumToInt(SCommand.ReadILinkModel   ) => cmdReadILinkModel(),
        @enumToInt(SCommand.BootCertify      ) => cmdBootCertify(),
        @enumToInt(SCommand.CancelPwOffReady ) => cmdCancelPwOffReady(),
        @enumToInt(SCommand.OpenConfig       ) => cmdOpenConfig(),
        @enumToInt(SCommand.ReadConfig       ) => cmdReadConfig(),
        @enumToInt(SCommand.CloseConfig      ) => cmdCloseConfig(),
        else => {
            std.debug.print("[CDVD      ] Unhandled S command 0x{X:0>2}.", .{cmd});

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
    std.debug.print("[CDVD      ] Seek. POS = {}, NUM = {}, SIZE = {}\n", .{seekParam.pos + sectorNum, seekParam.num, seekParam.size});

    cdvdFile.seekTo(seekParam.pos * seekParam.size) catch {
        std.debug.print("[CDVD      ] Unable to seek to sector\n", .{});

        assert(false);
    };

    const isDvd = nCmd == @enumToInt(NCommand.ReadDvd);

    var delta: i64 = @bitCast(i32, seekParam.pos) - @bitCast(i32, oldSectorNum);

    if (delta < 0) delta = -delta;

    if ((isDvd and delta < 16) or (!isDvd and delta < 8)) {
        // Contiguous read
        cyclesToSeek = getBlockTiming(isDvd) * delta;
    } else if ((isDvd and delta < 14764) or (!isDvd and delta < 4371)) {
        // Fast seek
        cyclesToSeek = iopClock / 33;
    } else {
        // Full seek
        cyclesToSeek = iopClock / 10;
    }

    if (delta != 0) {
        setDriveStat(0x12);
    } else {
        setDriveStat(6);
    }
}

/// Reads a CD sector
fn doReadCd() void {
    std.debug.print("[CDVD      ] Reading CD sector {}...\n", .{seekParam.pos + sectorNum});

    setDriveStat(0x06);

    cdvdFile.seekTo(seekParam.pos * seekParam.size + sectorNum * seekParam.size) catch {
        std.debug.print("[CDVD      ] Unable to seek to sector\n", .{});

        assert(false);
    };

    if (cdvdFile.reader().read(readBuf.buf[0..seekParam.size])) |bytesRead| {
        if (bytesRead != seekParam.size) {
            std.debug.print("[CDVD      ] Read size mismatch.", .{});

            assert(false);
        }
    } else |e| switch (e) {
        else => {
            std.debug.print("[moestation] Unhandled error {}.", .{e});

            assert(false);
        }
    }
}

/// Reads a DVD sector
fn doReadDvd() void {
    std.debug.print("[CDVD      ] Reading DVD sector {}...\n", .{seekParam.pos + sectorNum});

    setDriveStat(0x06);

    if (cdvdFile.reader().read(readBuf.buf[12..2060])) |bytesRead| {
        if (bytesRead != seekParam.size) {
            std.debug.print("[CDVD      ] Read size mismatch\n", .{});

            assert(false);
        }
    } else |e| switch (e) {
        else => {
            std.debug.print("[moestation] Unhandled error {}.", .{e});

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

/// BootCertify
fn cmdBootCertify() void {
    std.debug.print("[CDVD      ] BootCertify\n", .{});

    sCmdStat.noData = false;

    sCmdData.write(1);

    sCmdLen = 1;
}

/// CancelPwOffReady
fn cmdCancelPwOffReady() void {
    std.debug.print("[CDVD      ] CancelPwOffReady\n", .{});

    sCmdStat.noData = false;

    sCmdData.write(0);

    sCmdLen = 1;
}

/// OpenConfig
fn cmdCloseConfig() void {
    std.debug.print("[CDVD      ] CloseConfig\n", .{});

    sCmdStat.noData = false;
    
    sCmdData.write(0);

    sCmdLen = 1;
}

/// Forbid DVD
fn cmdForbidDvd() void {
    std.debug.print("[CDVD      ] ForbidDvd\n", .{});

    sCmdStat.noData = false;

    sCmdData.write(5);

    sCmdLen = 1;
}

/// Get TOC
fn cmdGetToc() void {
    std.debug.print("[CDVD      ] GetToc\n", .{});

    setDriveStat(0x06);

    seekParam.pos = 0;
    seekParam.num = 1;

    for (readBuf.buf[0..2064]) |*b| b.* = 0;

    readBuf.buf[0x00] = 0x04;
    readBuf.buf[0x01] = 0x02;
    readBuf.buf[0x02] = 0xF2;
    readBuf.buf[0x03] = 0x00;
    readBuf.buf[0x04] = 0x86;
    readBuf.buf[0x05] = 0x72;
    readBuf.buf[0x11] = 0x03;

    cyclesToRead = 1;
}

/// MechaconVersion
fn cmdMechaconVersion() void {
    std.debug.print("[CDVD      ] MechaconVersion\n", .{});

    sCmdStat.noData = false;

    sCmdData.write(0x03);
    sCmdData.write(0x06);
    sCmdData.write(0x02);
    sCmdData.write(0x00);

    sCmdLen = 4;
}

/// NOP
pub fn cmdNop() void {
    std.debug.print("[CDVD      ] NOP\n", .{});

    sendInterrupt();
}

/// OpenConfig
fn cmdOpenConfig() void {
    std.debug.print("[CDVD      ] OpenConfig\n", .{});

    sCmdStat.noData = false;

    sCmdData.write(0);

    sCmdLen = 1;
}

/// Pause
pub fn cmdPause() void {
    std.debug.print("[CDVD      ] Pause\n", .{});

    // Paused
    setDriveStat(8);

    nCmdStat = 0x40;

    intc.sendInterruptIop(IntSource.Cdvd);
}

/// ReadCd
fn cmdReadCd() void {
    std.debug.print("[CDVD      ] ReadCd\n", .{});

    seekParam.pos = @as(u32, nCmdParam.buf[0]) | (@as(u32, nCmdParam.buf[1]) << 8) | (@as(u32, nCmdParam.buf[2]) << 16) | (@as(u32, nCmdParam.buf[3]) << 24);
    seekParam.num = @as(u32, nCmdParam.buf[4]) | (@as(u32, nCmdParam.buf[5]) << 8) | (@as(u32, nCmdParam.buf[6]) << 16) | (@as(u32, nCmdParam.buf[7]) << 24);

    if (seekParam.num == 0) {
        std.debug.print("[CDVD      ] No sectors to read\n", .{});

        assert(false);
    }

    if (seekParam.pos >= 0x8000_0000) {
        std.debug.print("[CDVD      ] Negative sector number\n", .{});

        assert(false);
    }

    switch (nCmdParam.buf[10]) {
        0    => seekParam.size = 2048,
        1    => seekParam.size = 2328,
        2    => seekParam.size = 2340,
        else => {
            std.debug.print("[CDVD      ] Unhandled sector size {}.", .{nCmdParam.buf[10]});

            assert(false);
        },
    }

    if (nCmdParam.buf[10] != 0) {
        std.debug.print("[CDVD      ] Unhanded non-2048 byte CD sector.", .{});

        assert(false);
    }

    doSeek();
}

/// ReadConfig
fn cmdReadConfig() void {
    std.debug.print("[CDVD      ] ReadConfig\n", .{});

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
    std.debug.print("[CDVD      ] ReadDvd\n", .{});

    seekParam.pos  = @as(u32, nCmdParam.buf[0]) | (@as(u32, nCmdParam.buf[1]) << 8) | (@as(u32, nCmdParam.buf[2]) << 16) | (@as(u32, nCmdParam.buf[3]) << 24);
    seekParam.num  = @as(u32, nCmdParam.buf[4]) | (@as(u32, nCmdParam.buf[5]) << 8) | (@as(u32, nCmdParam.buf[6]) << 16) | (@as(u32, nCmdParam.buf[7]) << 24);
    seekParam.size = 2048;

    if (seekParam.num == 0) {
        std.debug.print("[CDVD      ] No sectors to read\n", .{});

        assert(false);
    }

    if (seekParam.pos >= 0x8000_0000) {
        std.debug.print("[CDVD      ] Negative sector number.", .{});

        assert(false);
    }

    doSeek();
}

/// ReadiLinkModel
fn cmdReadILinkModel() void {
    std.debug.print("[CDVD      ] ReadiLinkModel\n", .{});

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

    sCmdLen = 9;
}

/// ReadRtc
fn cmdReadRtc() void {
    std.debug.print("[CDVD      ] ReadRtc\n", .{});

    sCmdStat.noData = false;
    
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    sCmdData.write(0);
    
    sCmdData.write(0);
    sCmdData.write(1);
    sCmdData.write(0);
    sCmdData.write(0);

    sCmdLen = 8;
}

/// Update Sticky Flags
fn cmdUpdateStickyFlags() void {
    std.debug.print("[CDVD      ] UpdateStickyFlags\n", .{});

    sCmdStat.noData = false;

    sDriveStat = driveStat;

    sCmdData.write(0);

    sCmdLen = 1;
}

pub fn step() void {
    if (cyclesToRead >= 0) {
        cyclesToRead -= 1;

        if (cyclesToRead == 0) {
            dmac.setRequest(Channel.Cdvd, true);
        }
    }

    if (cyclesToSeek >= 0) {
        if (cyclesToSeek == 0) {
            const isDvd = nCmd == @enumToInt(NCommand.ReadDvd);

            if (isDvd) {
                doReadDvd();
            } else {
                doReadCd();
            }
            
            cyclesToRead = getBlockTiming(isDvd);
        }
        
        cyclesToSeek -= 1;
    }
}
