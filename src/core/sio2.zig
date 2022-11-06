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
    PadConnected = 0,
    McConnected  = 0x1000,
    NoDevice     = 0x1D100,
};

/// SIO2 Pad commands
const PadCommand = enum(u8) {
    ReadData   = 0x42,
    ConfigMode = 0x43,
};

/// Pad state
const PadState = enum(u8) {
    Digital = 0x41,
    Config  = 0xF3,
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
var padState = PadState.Digital;

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

            info("   [SIO2      ] Write @ 0x{X:0>2} (SIO2_FIFOIN) = 0x{X:0>2}.", .{addr, data});

            sio2FifoIn.writeItem(data) catch {
                err("  [SIO2      ] SIO2_FIFOIN is full.", .{});
        
                assert(false);
            };
        },
        @enumToInt(Sio2Reg.Sio2Ctrl) => {
            if (T != u32) {
                @panic("Unhandled write @ SIO2_CTRL");
            }

            info("   [SIO2      ] Write @ 0x{X:0>8} (SIO2_CTRL) = 0x{X:0>8}.", .{addr, data});

            if ((data & 0xC) == 0xC) {
                info("   [SIO2      ] SIO2 reset.", .{});

                sio2FifoIn  = Sio2Fifo.init();
                sio2FifoOut = Sio2Fifo.init();

                sio2Send3 = Sio2Send3.init();
            } else if ((data & 1) != 0) {
                doCmdChain();
            }

            sio2Ctrl = data & ~@as(u32, 0xD);
        },
        @enumToInt(Sio2Reg.Sio2IStat) => {
            if (T != u32) {
                @panic("Unhandled write @ SIO2_ISTAT");
            }

            info("   [SIO2      ] Write @ 0x{X:0>2} (SIO2_ISTAT) = 0x{X:0>8}.", .{addr, data});
        },
        else => {
            err("  [SIO2      ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X:0>8}.", .{@typeName(T), addr, data});

            assert(false);
        }
    }
}

/// Writes a byte to SIO2_FIFOOUT
fn writeFifoOut(data: u8) void {
    sio2FifoOut.writeItem(data) catch {
        err("  [SIO2      ] SIO2_FIFOOUT is full.", .{});
        
        assert(false);
    };
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
        Device.Controller => @enumToInt(DeviceStatus.PadConnected),
        Device.MemoryCard => @enumToInt(DeviceStatus.McConnected),
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
            else => {
                err("  [SIO2      ] Unhandled {s} command.", .{@tagName(activeDev)});

                assert(false);
            }
        }
    }

    updateDevStatus();

    intc.sendInterruptIop(IntSource.Sio2);
}

/// Executes a pad command
fn doPadCmd() void {
    const cmd = sio2FifoIn.readItem().?;

    switch (cmd) {
        @enumToInt(PadCommand.ReadData  ) => cmdPadReadData(),
        @enumToInt(PadCommand.ConfigMode) => cmdPadConfigMode(),
        else => {
            err("  [SIO2      ] Unhandled pad command 0x{X:0>2}.", .{cmd});

            assert(false);
        }
    }
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

        padState = PadState.Digital;
    }

    // Remove excess bytes from FIFOIN
    sio2FifoIn.discard(send3.len - 4);

    // Send header reply
    writeFifoOut(0xFF);
    writeFifoOut(@enumToInt(oldState));
    writeFifoOut(0x5A);

    if (isEnter) {
        // Send button state
        writeFifoOut(0xFF);
        writeFifoOut(0xFF);
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
    writeFifoOut(0xFF);
    writeFifoOut(0xFF);
}
