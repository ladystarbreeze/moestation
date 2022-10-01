//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cpu.zig - EmotionEngine Core interpreter
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const bus = @import("bus.zig");

const exts = @import("../common/extend.zig").exts;

const resetVector: u32 = 0xBFC0_0000;

/// Register aliases
const CpuReg = enum(u5) {
    R0 =  0, AT =  1, V0 =  2, V1 =  3,
    A0 =  4, A1 =  5, A2 =  6, A3 =  7,
    T0 =  8, T1 =  9, T2 = 10, T3 = 11,
    T4 = 12, T5 = 13, T6 = 14, T7 = 15,
    S0 = 16, S1 = 17, S2 = 18, S3 = 19,
    S4 = 20, S5 = 21, S6 = 22, S7 = 23,
    T8 = 24, T9 = 25, K0 = 26, K1 = 27,
    GP = 28, SP = 29, S8 = 30, RA = 31,
};

/// EE Core General-purpose register
const Gpr = struct {
    lo: u64 = undefined,
    hi: u64 = undefined,

    /// Returns GPR
    pub fn get(self: Gpr, comptime T: type) T {
        assert(T == u32 or T == u64 or T == u128);

        var data: T = undefined;

        switch (T) {
            u32  => data = @truncate(u32, self.lo),
            u64  => data = self.lo,
            u128 => data = (@as(u128, self.hi) << 64) | @as(u128, self.lo),
        }

        return data;
    }

    /// Sets GPR
    pub fn set(self: *Gpr, comptime T: type, data: T) void {
        assert(T == u32 or T == u64 or T == u128);

        switch (T) {
            u32  => self.lo = exts(u64, T, data),
            u64  => self.lo = data,
            u128 => {
                self.lo = @truncate(u64, data);
                self.hi = @truncate(u64, data >> 64);
            },
        }
    }
};

/// EE Core register file
const RegFile = struct {
    // GPRs
    regs: [32]Gpr = undefined,

    // Program counters
     pc: u32 = undefined,
    cpc: u32 = undefined,
    npc: u32 = undefined,

    /// Returns GPR
    pub fn get(self: RegFile, comptime T: type, idx: u5) T {
        return self.regs[idx].get(T);
    }

    /// Sets GPR
    pub fn set(self: *RegFile, comptime T: type, idx: u5, data: u32) void {
        self.regs[idx].set(T, data);

        self.regs[0].set(u128, 0);
    }

    /// Sets program counter
    pub fn setPc(self: *RegFile, data: u32) void {
        assert((data & 3) == 0);
    
        self.pc  = data;
        self.npc = data +% 4;
    }

    /// Advances program counter
    pub fn stepPc(self: *RegFile) void {
        self.pc = self.npc;
        self.npc +%= 4;
    }
};

/// RegFile instance
var regFile = RegFile{};

/// Initializes the EE Core interpreter
pub fn init() void {
    regFile.setPc(resetVector);

    info("   [EE Core   ] Successfully initialized.", .{});
}

/// Translates virtual address to physical address
fn translateAddr(addr: u32) u32 {
    // NOTE: this is Kernel mode only!
    var pAddr: u32 = undefined;

    switch (@truncate(u4, addr >> 28)) {
        0x8 ... 0x9, 0xA ... 0xB => {
            pAddr = addr & 0x1FFF_FFFF;
        },
        0x0 ... 0x7, 0xC ... 0xF => {
            err("  [EE Core   ] Unhandled TLB area @ 0x{X:0>8}.", .{addr});

            assert(false);
        },
    }

    return pAddr;
}

/// Reads data from the system bus
fn read(comptime T: type, addr: u32) T {
    return bus.read(T, translateAddr(addr));
}

/// Fetches an instruction from memory and increments PC
fn fetchInstr() u32 {
    const instr = read(u32, regFile.pc);

    regFile.stepPc();

    return instr;
}

/// Writes data to the system bus
fn write(comptime T: type, addr: u32, data: T) void {
    bus.write(T, translateAddr(addr), data);
}

/// Decodes and executes instructions
fn decodeInstr(instr: u32) void {
    err("  [EE Core   ] Unhandled instruction 0x{X:0>8}.", .{instr});

    assert(false);
}

/// Steps the EE Core interpreter
pub fn step() void {
    regFile.cpc = regFile.pc;

    decodeInstr(fetchInstr());
}
