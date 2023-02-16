//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! core/sio2.zig - Controller/Memory Card module
//!

const std = @import("std");

const assert = std.debug.assert;

const LinearFifo = std.fifo.LinearFifo;
const LinearFifoBufferType = std.fifo.LinearFifoBufferType;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const dmac = @import("dmac_iop.zig");

const Channel = dmac.Channel;

const intc = @import("intc.zig");

const IntSource = intc.IntSourceIop;

/// SIO2 registers
const Sio2Reg = enum(u32) {
    Sio2Send3   = 0x1F80_8200,
    Sio2Send1   = 0x1F80_8240,
    Sio2FifoIn  = 0x1F80_8260,
    Sio2FifoOut = 0x1F80_8264,
    Sio2Ctrl    = 0x1F80_8268,
    Sio2Recv1   = 0x1F80_826C,
    Sio2Recv2   = 0x1F80_8270,
    Sio2Recv3   = 0x1F80_8274,
    Sio2IStat   = 0x1F80_8280,
};

/// SEND3
const Send3 = struct {
    port: u2 = 0,
     len: u6 = 0,
};

/// SIO2 devices
const Device = enum(u8) {
    Controller = 0x01,
    Multitap   = 0x21,
    Infrared   = 0x61,
    MemoryCard = 0x81,
};

/// Device status
const DeviceStatus = enum(u32) {
    Connected = 0x1100,
    NoDevice  = 0x1D100,
};

/// SIO2 Pad commands
const PadCommand = enum(u8) {
    SetVrefParam    = 0x40,
    QueryMaskedMode = 0x41,
    ReadData        = 0x42,
    ConfigMode      = 0x43,
    SetModeAndLock  = 0x44,
    QueryModel      = 0x45,
    QueryAct        = 0x46,
    QueryComb       = 0x47,
    QueryMode       = 0x4C,
    VibrationToggle = 0x4D,
    SetNativeMode   = 0x4F,
};

/// Memory Card command
const McCommand = enum(u8) {
    Probe         = 0x11,
    GetTerminator = 0x28,
    ReadDataPsx   = 0x52,
    AuthF3        = 0xF3,
};

/// Pad state
const PadState = enum(u8) {
    Digital    = 0x41,
    DualShock2 = 0x79,
    Config     = 0xF3,
};

/// SIO2 FIFOs (FIFOIN/OUT, SEND3)
const Sio2Fifo  = LinearFifo(u8, LinearFifoBufferType{.Static = 256});
const Sio2Send3 = LinearFifo(u32, LinearFifoBufferType{.Static = 16});

/// SIO2_CTRL (stub)
var sio2Ctrl: u32 = 0;

/// SIO2_SEND1/2 (stub)
var sio2Send1: [8]u32 = undefined;

/// SIO2_SEND3
var sio2Send3 = Sio2Send3.init();
var send3 = Send3{};

/// SIO2_FIFOIN/OUT
var sio2FifoIn  = Sio2Fifo.init();
var sio2FifoOut = Sio2Fifo.init();

/// SIO2_RECV1
var sio2Recv1: u32 = undefined;

/// Active SIO2 device
var activeDev: Device = undefined;

/// Pad state
var padState = PadState.DualShock2;

var buttonState: u16 = 0xFFFF;

/// Rumble values (stub)
var rumble = [_]u8 {0x5A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

/// Terminator byte
var terminator: u8 = 0x55;

var replySize: u9 = 0;

/// Reads data from SIO2
pub fn read(comptime T: type, addr: u32) T {
    var data: T = undefined;

    switch (addr) {
        @enumToInt(Sio2Reg.Sio2FifoOut) => {
            if (T != u8) {
                @panic("Unhandled read @ SIO2_FIFOOUT");
            }

            info("   [SIO2      ] Read @ 0x{X:0>8} (SIO2_FIFOOUT).", .{addr});

            data = sio2FifoOut.readItem().?;

            if (sio2FifoOut.readableLength() < 4) {
                dmac.setRequest(Channel.Sio2Out, false);
            }
        },
        @enumToInt(Sio2Reg.Sio2Ctrl) => {
            if (T != u32) {
                @panic("Unhandled read @ SIO2_CTRL");
            }

            info("   [SIO2      ] Read @ 0x{X:0>8} (SIO2_CTRL).", .{addr});

            data = sio2Ctrl;
        },
        @enumToInt(Sio2Reg.Sio2Recv1) => {
            if (T != u32) {
                @panic("Unhandled read @ SIO2_REVC1");
            }

            info("   [SIO2      ] Read @ 0x{X:0>8} (SIO2_RECV1).", .{addr});

            data = sio2Recv1;
        },
        @enumToInt(Sio2Reg.Sio2Recv2) => {
            if (T != u32) {
                @panic("Unhandled read @ SIO2_REVC2");
            }

            info("   [SIO2      ] Read @ 0x{X:0>8} (SIO2_RECV2).", .{addr});

            // This register supposedly always returns 0xF?
            data = 0xF;
        },
        @enumToInt(Sio2Reg.Sio2Recv3) => {
            if (T != u32) {
                @panic("Unhandled read @ SIO2_RECV3");
            }

            info("   [SIO2      ] Read @ 0x{X:0>8} (SIO2_RECV3).", .{addr});

            // No idea what to return here
            data = 0;
        },
        @enumToInt(Sio2Reg.Sio2IStat) => {
            if (T != u32) {
                @panic("Unhandled read @ SIO2_ISTAT");
            }

            info("   [SIO2      ] Read @ 0x{X:0>8} (SIO2_ISTAT).", .{addr});

            // No idea what to return here
            data = 0;
        },
        else => {
            err("  [SIO2      ] Unhandled read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

            assert(false);
        }
    }

    return data;
}

/// Reads data from FIFOOUT
pub fn readDmac() u32 {
    info("   [SIO2      ] Read @ (SIO2_FIFOOUT).", .{});

    const data = @as(u32, sio2FifoOut.readItem().?) | (@as(u32, sio2FifoOut.readItem().?) << 8) | (@as(u32, sio2FifoOut.readItem().?) << 16) | (@as(u32, sio2FifoOut.readItem().?) << 24);

    if (sio2FifoOut.readableLength() < 4) {
        dmac.setRequest(Channel.Sio2Out, false);
    }

    return data;
}

/// Writes data to SIO2
pub fn write(comptime T: type, addr: u32, data: T) void {
    switch (addr) {
        @enumToInt(Sio2Reg.Sio2Send3) ... @enumToInt(Sio2Reg.Sio2Send3) + 0x3F => {
            if (T != u32) {
                @panic("Unhandled write @ SIO2_SEND3");
            }

            info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_SEND3) = 0x{X:0>8}.", .{addr, data});

            // Don't send empty SIO2 command parameters to FIFO
            if (data != 0) {
                sio2Send3.writeItem(data) catch {
                    err("  [SIO2      ] SIO2_SEND3 is full.", .{});
        
                    assert(false);
                };
            }
        },
        @enumToInt(Sio2Reg.Sio2Send1) ... @enumToInt(Sio2Reg.Sio2Send1) + 0x1F => {
            if (T != u32) {
                @panic("Unhandled write @ SIO2_SEND1/2");
            }

            if ((addr & 4) == 0) {
                info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_SEND1) = 0x{X:0>8}.", .{addr, data});
            } else {
                info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_SEND2) = 0x{X:0>8}.", .{addr, data});
            }

            sio2Send1[(addr - @enumToInt(Sio2Reg.Sio2Send1)) >> 2] = data;
        },
        @enumToInt(Sio2Reg.Sio2FifoIn) => {
            if (T != u8) {
                @panic("Unhandled write @ SIO2_FIFOIN");
            }

            info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_FIFOIN) = 0x{X:0>2}.", .{addr, data});

            sio2FifoIn.writeItem(data) catch {
                err("  [SIO2      ] SIO2_FIFOIN is full.", .{});
        
                assert(false);
            };

            replySize += 1;

            if (sio2FifoOut.readableLength() >= 252) {
                dmac.setRequest(Channel.Sio2In, false);
            }
        },
        @enumToInt(Sio2Reg.Sio2Ctrl) => {
            if (T != u32) {
                @panic("Unhandled write @ SIO2_CTRL");
            }

            info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_CTRL) = 0x{X:0>8}.", .{addr, data});

            sio2Ctrl = data;

            if ((data & 0xC) == 0xC) {
                info("   [SIO2      ] SIO2 reset.", .{});

                sio2FifoIn  = Sio2Fifo.init();
                sio2FifoOut = Sio2Fifo.init();

                sio2Send3 = Sio2Send3.init();

                replySize = 0;

                dmac.setRequest(Channel.Sio2In, true);
                dmac.setRequest(Channel.Sio2Out, false);

                sio2Ctrl &= ~@as(u32, 0xC);
            }
            
            if ((data & 1) != 0) {
                doCmdChain();

                sio2Ctrl &= ~@as(u32, 1);
            }
        },
        @enumToInt(Sio2Reg.Sio2IStat) => {
            if (T != u32) {
                @panic("Unhandled write @ SIO2_ISTAT");
            }

            info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_ISTAT) = 0x{X:0>8}.", .{addr, data});
        },
        else => {
            err("  [SIO2      ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X:0>8}.", .{@typeName(T), addr, data});

            assert(false);
        }
    }
}

/// Writes a word to SIO2_FIFOIN
pub fn writeDmac(data: u32) void {
    info("   [SIO2      ] Write @ SIO2_FIFOIN = 0x{X:0>8}.", .{data});

    var i: u5 = 0;
    while (i < 4) : (i += 1) {
        sio2FifoIn.writeItem(@truncate(u8, data >> (8 * i))) catch {
            err("  [SIO2      ] Unable to write to SIO2_FIFOIN.", .{});
            
            assert(false);
        };
    }

    replySize += 4;

    if (sio2FifoOut.readableLength() >= 252) {
        dmac.setRequest(Channel.Sio2In, false);
    }
}

/// Writes a byte to SIO2_FIFOOUT
fn writeFifoOut(data: u8) void {
    sio2FifoOut.writeItem(data) catch {
        err("  [SIO2      ] SIO2_FIFOOUT is full.", .{});
        
        assert(false);
    };

    replySize -= 1;

    if (sio2FifoOut.readableLength() >= 4) {
        dmac.setRequest(Channel.Sio2Out, true);
    }
}

/// Sets button state
pub fn setButtonState(newState: u16) void {
    buttonState = newState;

    //std.debug.print("[SIO2      ] New button state: 0b{b:0>16}\n", .{buttonState});
}

/// Returns an SIO2 device
fn getDevice(data: u8) Device {
    var dev: Device = undefined;

    switch (data) {
        @enumToInt(Device.Controller) => {
            dev = Device.Controller;
        },
        @enumToInt(Device.Multitap) => {
            dev = Device.Multitap;
        },
        @enumToInt(Device.Infrared) => {
            dev = Device.Infrared;
        },
        @enumToInt(Device.MemoryCard) => {
            dev = Device.MemoryCard;
        },
        else => {
            err("  [SIO2      ] Unhandled device 0x{X:0>2}.", .{data});

            assert(false);
        }
    }

    return dev;
}

/// Updates device status (RECV1)
fn updateDevStatus() void {
    // sio2Recv1 = @enumToInt(DeviceStatus.NoDevice);

    sio2Recv1 = switch (activeDev) {
        Device.Controller => if (send3.port == 0) @enumToInt(DeviceStatus.Connected) else @enumToInt(DeviceStatus.NoDevice),
        else => @enumToInt(DeviceStatus.NoDevice),
    };
}

/// Executes a SIO2 command chain
fn doCmdChain() void {
    info("   [SIO2      ] New command chain.", .{});

    if (sio2Send3.readableLength() == 0) {
        err("  [SIO2      ] No command parameters in SIO2_SEND3.", .{});
        
        assert(false);
    }

    while (sio2Send3.readableLength() > 0) {
        const data = sio2Send3.readItem().?;

        send3.port = @truncate(u2, data);
        send3.len  = @truncate(u6, data >> 18);

        info("   [SIO2      ] New command. Port = {}, Length = {}", .{send3.port, send3.len});

        // Is it okay to ignore SEND3?
        activeDev = getDevice(sio2FifoIn.readItem().?);

        switch (activeDev) {
            Device.Controller => doPadCmd(),
            //Device.MemoryCard => doMcCmd(),
            Device.MemoryCard, Device.Infrared, Device.Multitap => {
                sio2FifoIn.discard(send3.len - 1);
            }
        }
    }

    while (replySize != 0) {
        writeFifoOut(0);
    }

    updateDevStatus();

    intc.sendInterruptIop(IntSource.Sio2);
}

/// Executes a pad command
fn doPadCmd() void {
    const cmd = sio2FifoIn.readItem().?;

    switch (cmd) {
        @enumToInt(PadCommand.SetVrefParam   ) => cmdPadSetVrefParam(),
        @enumToInt(PadCommand.QueryMaskedMode) => cmdPadQueryMaskedMode(),
        @enumToInt(PadCommand.ReadData       ) => cmdPadReadData(),
        @enumToInt(PadCommand.ConfigMode     ) => cmdPadConfigMode(),
        @enumToInt(PadCommand.SetModeAndLock ) => cmdPadSetModeAndLock(),
        @enumToInt(PadCommand.QueryModel     ) => cmdPadQueryModel(),
        @enumToInt(PadCommand.QueryAct       ) => cmdPadQueryAct(),
        @enumToInt(PadCommand.QueryComb      ) => cmdPadQueryComb(),
        @enumToInt(PadCommand.QueryMode      ) => cmdPadQueryMode(),
        @enumToInt(PadCommand.VibrationToggle) => cmdPadVibrationToggle(),
        @enumToInt(PadCommand.SetNativeMode  ) => cmdPadSetNativeMode(),
        else => {
            err("  [SIO2      ] Unhandled pad command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }
}

/// Executes a Memory Card command
fn doMcCmd() void {
    const cmd = sio2FifoIn.readItem().?;

    switch (cmd) {
        @enumToInt(McCommand.Probe      ) => cmdMcProbe(),
        @enumToInt(McCommand.ReadDataPsx) => cmdMcReadDataPsx(),
        @enumToInt(McCommand.AuthF3     ) => cmdMcAuthF3(),
        else => {
            err("  [SIO2      ] Unhandled Memory Card command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }
}

/// Memory Card AuthF3
fn cmdMcAuthF3() void {
    info("   [SIO2 (MC) ] AuthF3", .{});

    // Get XX byte
    const xx = sio2FifoIn.readItem().? | sio2FifoIn.readItem().?;

    // Send reply
    writeFifoOut(xx);
    writeFifoOut(0x2B);
    writeFifoOut(terminator);
}

/// Memory Card Probe
fn cmdMcProbe() void {
    info("   [SIO2 (MC) ] Probe", .{});

    // Remove excessive command bytes
    sio2FifoIn.discard(1);

    // Send reply
    writeFifoOut(0x2B);
    writeFifoOut(terminator);
}

/// Memory Card Read Data (PSX style)
fn cmdMcReadDataPsx() void {
    info("   [SIO2 (MC) ] Read Data (PSX)", .{});

    // Remove excessive command bytes
    sio2FifoIn.discard(1);

    // Send reply
    writeFifoOut(0x08);
    writeFifoOut(0x2B);
    writeFifoOut(terminator);
}

/// Pad Enter/Exit Config Mode
fn cmdPadConfigMode() void {
    // Remove header
    sio2FifoIn.discard(1);

    const isEnter = if (sio2FifoIn.readItem().? == 1) true else false;

    const oldState = padState;

    if (isEnter) {
        info("   [SIO2 (Pad)] Enter Config Mode", .{});

        padState = PadState.Config;
    } else {
        info("   [SIO2 (Pad)] Exit Config Mode", .{});

        padState = PadState.DualShock2;
    }

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 4);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(@enumToInt(oldState));
    writeFifoOut(0x5A);

    if (isEnter) {
        // Send button state
        writeFifoOut(@truncate(u8, buttonState));
        writeFifoOut(@truncate(u8, buttonState >> 8));
        writeFifoOut(0x80);
        writeFifoOut(0x80);
        writeFifoOut(0x80);
        writeFifoOut(0x80);
    } else {
        // Send six 0 bytes
        writeFifoOut(0);
        writeFifoOut(0);
        writeFifoOut(0);
        writeFifoOut(0);
        writeFifoOut(0);
        writeFifoOut(0);
    }
}

/// Pad Query Act
fn cmdPadQueryAct() void {
    info("   [SIO2 (Pad)] Query Act", .{});

    // Remove header
    sio2FifoIn.discard(1);

    const index = sio2FifoIn.readItem().? == 1;

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 4);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    if (index) {
        writeFifoOut(0x00);
        writeFifoOut(0x00);
        writeFifoOut(0x01);
        writeFifoOut(0x01);
        writeFifoOut(0x01);
        writeFifoOut(0x14);
    } else {
        writeFifoOut(0x00);
        writeFifoOut(0x00);
        writeFifoOut(0x01);
        writeFifoOut(0x02);
        writeFifoOut(0x00);
        writeFifoOut(0x0A);
    }
}

/// Pad Query Comb
fn cmdPadQueryComb() void {
    info("   [SIO2 (Pad)] Query Comb", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x02);
    writeFifoOut(0x00);
    writeFifoOut(0x01);
    writeFifoOut(0x00);
}

/// Pad Query Masked Mode
fn cmdPadQueryMaskedMode() void {
    info("   [SIO2 (Pad)] Query Masked Mode", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    // Send 0 bytes (analog)
    writeFifoOut(0xFF);
    writeFifoOut(0xFF);
    writeFifoOut(0xFF);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x5A);
}

/// Pad Query Mode
fn cmdPadQueryMode() void {
    info("   [SIO2 (Pad)] Query Mode", .{});

    // Remove header
    sio2FifoIn.discard(1);

    const index = sio2FifoIn.readItem().? == 1;

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 4);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);

    if (index) {
        writeFifoOut(0x07);
    } else {
        writeFifoOut(0x04);
    }

    writeFifoOut(0x00);
    writeFifoOut(0x00);
}

/// Pad Query Model
fn cmdPadQueryModel() void {
    info("   [SIO2 (Pad)] Query Model", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    writeFifoOut(0x03); // Send model (DualShock 2)
    writeFifoOut(0x02);
    writeFifoOut(0x01); // Send mode (analog)
    writeFifoOut(0x02);
    writeFifoOut(0x01);
    writeFifoOut(0x00);
}

/// Pad Read Data
fn cmdPadReadData() void {
    info("   [SIO2 (Pad)] Read Data", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(@enumToInt(padState));
    writeFifoOut(0x5A);

    // Send button state
    writeFifoOut(@truncate(u8, buttonState));
    writeFifoOut(@truncate(u8, buttonState >> 8));

    if (send3.len > 5) {
        // Send analog button state
        writeFifoOut(0x80);
        writeFifoOut(0x80);
        writeFifoOut(0x80);
        writeFifoOut(0x80);
    }
}

/// Pad Set Mode and Lock
fn cmdPadSetModeAndLock() void {
    info("   [SIO2 (Pad)] Set Mode and Lock", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    // Send 0 bytes
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);

    rumble = [_]u8 {0x5A, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
}

/// Pad Set Native Mode
fn cmdPadSetNativeMode() void {
    info("   [SIO2 (Pad)] Set Native Mode", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    // Send 0 bytes
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x5A);
}

/// Pad Set VREF Param
fn cmdPadSetVrefParam() void {
    info("   [SIO2 (Pad)] Set VREF Param", .{});

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 2);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    // Send 0 bytes
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x02);
    writeFifoOut(0x00);
    writeFifoOut(0x00);
    writeFifoOut(0x5A);
}

/// Pad Vibration Toggle
fn cmdPadVibrationToggle() void {
    info("   [SIO2 (Pad)] Vibration Toggle", .{});

    // Remove header
    sio2FifoIn.discard(1);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(0xF3);
    writeFifoOut(0x5A);

    // Send old rumble values
    writeFifoOut(rumble[0]);
    writeFifoOut(rumble[1]);
    writeFifoOut(rumble[2]);
    writeFifoOut(rumble[3]);
    writeFifoOut(rumble[4]);
    writeFifoOut(rumble[5]);

    // Get new rumble values
    rumble[0] = sio2FifoIn.readItem().?;
    rumble[1] = sio2FifoIn.readItem().?;
    rumble[2] = sio2FifoIn.readItem().?;
    rumble[3] = sio2FifoIn.readItem().?;
    rumble[4] = sio2FifoIn.readItem().?;
    rumble[5] = sio2FifoIn.readItem().?;
}
