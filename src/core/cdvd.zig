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

/// CDVD registers
const CdvdReg = enum(u32) {
    NCmdStat = 0x1F40_2005,
    SCmd     = 0x1F40_2016,
    SCmdStat = 0x1F40_2017,
    SCmdData = 0x1F40_2018,
};

/// S commands
const SCommand = enum(u8) {
    OpenConfig  = 0x40,
    ReadConfig  = 0x41,
    CloseConfig = 0x43,
};

/// N command status
const NCmdStat = struct {
    rdy: bool = true,
    bsy: bool = false,

    /// Returns N command status register
    pub fn get(self: NCmdStat) u8 {
        var data: u8 = 0;

        data |= @as(u8, @bitCast(u1, self.rdy)) << 6;
        data |= @as(u8, @bitCast(u1, self.bsy)) << 7;

        return data | 8;
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

/// CDVD registers
var sCmd: u8 = undefined;
var sCmdLen: u8 = undefined;

var nCmdStat: NCmdStat = NCmdStat{};
var sCmdStat: SCmdStat = SCmdStat{};

/// Returns a CDVD register
pub fn read(addr: u32) u8 {
    var data: u8 = undefined;

    switch (addr) {
        @enumToInt(CdvdReg.NCmdStat) => {
            info("   [CDVD      ] Read @ 0x{X:0>8} (N Command Status).", .{addr});

            data = nCmdStat.get();
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

/// Writes data to a CDVD register
pub fn write(addr: u32, data: u8) void {
    switch (addr) {
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

/// Calls S command handler
fn runSCmd(cmd: u8) void {
    sCmd = cmd;

    switch (cmd) {
        @enumToInt(SCommand.OpenConfig) => cmdOpenConfig(),
        @enumToInt(SCommand.ReadConfig) => cmdReadConfig(),
        @enumToInt(SCommand.CloseConfig) => cmdCloseConfig(),
        else => {
            err("  [CDVD      ] Unhandled S command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }
}

/// OpenConfig
fn cmdOpenConfig() void {
    info("   [CDVD      ] OpenConfig", .{});
}

/// ReadConfig
fn cmdReadConfig() void {
    info("   [CDVD      ] ReadConfig", .{});

    sCmdStat.noData = false;

    sCmdLen = 4 * 4;
}

/// OpenConfig
fn cmdCloseConfig() void {
    info("   [CDVD      ] CloseConfig", .{});
}
