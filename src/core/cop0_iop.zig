//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cop0.zig - IOP COP0
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const Cop0Reg = @import("cop0.zig").Cop0Reg;

const iop = @import("iop.zig");

/// Exception codes
pub const ExCode = enum(u5) {
    Interrupt,
    TlbModification,
    TlbLoad,
    TlbStore,
    AddressErrorLoad,
    AddressErrorStore,
    InstructionBusError,
    DataBusError,
    Syscall,
    Breakpoint,
    ReservedInstruction,
    CoprocessorUnusable,
    Overflow,
};

/// COP0 Cause register
const Cause = struct {
    excode: u5   = undefined,
        ip: u8   = undefined,
        ce: u2   = undefined,
        bd: bool = undefined,

    /// Returns Cause
    pub fn get(self: Cause) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.excode) << 2;
        data |= @as(u32, self.ip) << 8;
        data |= @as(u32, self.ce) << 28;
        data |= @as(u32, @bitCast(u1, self.bd)) << 31;

        return data;
    }

    /// Sets Cause
    pub fn set(self: *Cause, data: u32) void {
        self.ip = @truncate(u8, data >> 8);
    }
};

/// COP0 Status register
const Status = struct {
    cie: bool = undefined, // Current Interrupt Enable
    cku: bool = undefined, // Current Kernel/User mode
    pie: bool = undefined, // Previous Interrupt Enable
    pku: bool = undefined, // Previous Kernel/User mode
    oie: bool = undefined, // Old Interrupt Enable
    oku: bool = undefined, // Old Kernel/User mode
     im: u8   = undefined, // Interrupt Mask
    isc: bool = undefined, // ISolate Cache
    swc: bool = undefined, // SWap Caches
     pz: bool = undefined, // cache Parity Zero
     ch: bool = undefined, // Cache Hit
     pe: bool = undefined, // cache Parity Error
     ts: bool = undefined, // TLB Shutdown
    bev: bool = true,      // Boot Exception Vector
     re: bool = undefined, // Reverse Endianness
     cu: u4   = undefined, // Coprocessor Usable

    // Returns Status
    pub fn get(self: Status) u32 {
        var data: u32 = 0;

        data |= @as(u32, @bitCast(u1, self.cie));
        data |= @as(u32, @bitCast(u1, self.cku)) << 1;
        data |= @as(u32, @bitCast(u1, self.pie)) << 2;
        data |= @as(u32, @bitCast(u1, self.pku)) << 3;
        data |= @as(u32, @bitCast(u1, self.oku)) << 4;
        data |= @as(u32, @bitCast(u1, self.oku)) << 5;
        data |= @as(u32, self.im) << 8;
        data |= @as(u32, @bitCast(u1, self.isc)) << 16;
        data |= @as(u32, @bitCast(u1, self.swc)) << 17;
        data |= @as(u32, @bitCast(u1, self.pz )) << 18;
        data |= @as(u32, @bitCast(u1, self.ch )) << 19;
        data |= @as(u32, @bitCast(u1, self.pe )) << 20;
        data |= @as(u32, @bitCast(u1, self.ts )) << 21;
        data |= @as(u32, @bitCast(u1, self.bev)) << 22;
        data |= @as(u32, @bitCast(u1, self.re )) << 25;
        data |= @as(u32, self.cu) << 28;

        return data;
    }

    /// Sets Status
    pub fn set(self: *Status, data: u32) void {
        self.cie = (data & 1) != 0;
        self.cku = (data & (1 << 1)) != 0;
        self.pie = (data & (1 << 2)) != 0;
        self.pku = (data & (1 << 3)) != 0;
        self.oie = (data & (1 << 4)) != 0;
        self.oku = (data & (1 << 5)) != 0;
        self.im  = @truncate(u8, data >> 8);
        self.isc = (data & (1 << 16)) != 0;
        self.swc = (data & (1 << 17)) != 0;
        self.pz  = (data & (1 << 18)) != 0;
        self.ch  = (data & (1 << 19)) != 0;
        self.pe  = (data & (1 << 20)) != 0;
        self.ts  = (data & (1 << 21)) != 0;
        self.bev = (data & (1 << 22)) != 0;
        self.re  = (data & (1 << 25)) != 0;
        self.cu  = @truncate(u4, data >> 28);
    }
};

/// COP0 registers
var compare: u32 = undefined;
var   count: u32 = undefined;
var     epc: u32 = undefined;

var  cause: Cause  = Cause{};
var status: Status = Status{};

/// Returns true if boot exception vectors are active
pub fn isBev() bool {
    return status.bev;
}

/// Returns true if a coprocessor is usable
pub fn isCopUsable(comptime n: u2) bool {
    return n == 0 or (status.cu & (1 << n)) != 0;
}

/// Returns true if data cache is isolated
pub fn isCacheIsolated() bool {
    return status.isc;
}

/// Saves the current interrupt enable and privilege level bits
pub fn enterException() void {
    status.oie = status.pie;
    status.pie = status.cie;
    status.cie = false;

    status.oku = status.pku;
    status.pku = status.cku;
    status.cku = true;
}

/// Restores IE and KU bits
pub fn leaveException() void {
    status.cie = status.pie;
    status.pie = status.oie;

    status.cku = status.pku;
    status.pku = status.oku;

    iop.checkIntPending();
}

/// Returns a COP0 register
pub fn get(idx: u5) u32 {
    var data: u32 = undefined;

    switch (idx) {
        @enumToInt(Cop0Reg.Status) => data = status.get(),
        @enumToInt(Cop0Reg.Cause ) => data = cause.get(),
        @enumToInt(Cop0Reg.EPC   ) => data = epc,
        @enumToInt(Cop0Reg.PRId  ) => data = 0x1F,
        else => {
            err("  [COP0 (IOP)] Unhandled register read @ {s}.", .{@tagName(@intToEnum(Cop0Reg, idx))});

            assert(false);
        }
    }

    //info("   [COP0 (IOP)] Register read @ {s}.", .{@tagName(@intToEnum(Cop0Reg, idx))});

    return data;
}

/// Returns interrupt enable flag in Status
pub fn getCie() bool {
    return status.cie;
}

/// Returns interrupt mask in Status
pub fn getIm() u8 {
    return status.im;
}

/// Returns interrupt pending field in Cause
pub fn getIp() u8 {
    return cause.ip;
}

/// Sets a COP0 register
pub fn set(idx: u5, data: u32) void {
    switch (idx) {
        @enumToInt(Cop0Reg.EntryLo1) => {},
        @enumToInt(Cop0Reg.PageMask) => {},
        @enumToInt(Cop0Reg.Wired   ) => {},
        @enumToInt(Cop0Reg.R7      ) => {},
        @enumToInt(Cop0Reg.Count   ) => count = data,
        @enumToInt(Cop0Reg.Compare ) => compare = data,
        @enumToInt(Cop0Reg.Status  ) => {
            status.set(data);

            iop.checkIntPending();
        },
        @enumToInt(Cop0Reg.Cause   ) => {
            cause.set(data);

            iop.checkIntPending();
        },
        else => {
            err("  [COP0 (IOP)] Unhandled register write @ {s} = 0x{X:0>8}.", .{@tagName(@intToEnum(Cop0Reg, idx)), data});

            assert(false);
        }
    }

    //info("   [COP0 (IOP)] Register write @ {s} = 0x{X:0>8}.", .{@tagName(@intToEnum(Cop0Reg, idx)), data});
}

/// Sets BD bit
pub fn setBranchDelay(bd: bool) void {
    cause.bd = bd;
}

/// Sets EPC
pub fn setErrorPc(pc: u32) void {
    epc = pc;
}

/// Sets exception code
pub fn setExCode(excode: ExCode) void {
    cause.excode = @enumToInt(excode);
}

/// Sets Cause.10
pub fn setPending(irq: bool) void {
    cause.ip &= ~(@as(u8, 1) << 2);

    cause.ip |= @as(u8, @bitCast(u1, irq)) << 2;
}
