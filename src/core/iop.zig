//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! iop.zig - IOP interpreter
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const bus = @import("bus.zig");

const cop0 = @import("cop0_iop.zig");

const exts = @import("../common/extend.zig").exts;

/// Enable/disable disassembler
var doDisasm = true;

const resetVector: u32 = 0xBFC0_0000;

/// Branch delay slot helper
var inDelaySlot: [2]bool = undefined;

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

/// Opcodes
const Opcode = enum(u6) {
    Special = 0x00,
    Bne     = 0x05,
    Slti    = 0x0A,
    Ori     = 0x0D,
    Lui     = 0x0F,
    Cop0    = 0x10,
};

/// SPECIAL instructions
const Special = enum(u6) {
    Sll = 0x00,
    Jr  = 0x08,
};

/// COP instructions
const CopOpcode = enum(u5) {
    Mf = 0x00,
};

/// IOP register file
const RegFile = struct {
    // GPRs
    regs: [32]u32 = undefined,

    // Program counters
     pc: u32 = undefined,
    cpc: u32 = undefined,
    npc: u32 = undefined,

    lo: u32 = undefined,
    hi: u32 = undefined,

    /// Returns GPR
    pub fn get(self: RegFile, idx: u5) u32 {
        return self.regs[idx];
    }

    /// Sets GPR
    pub fn set(self: *RegFile, idx: u5, data: u32) void {
        self.regs[idx] = data;

        self.regs[0] = 0;
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

/// Initializes IOP interpreter
pub fn init() void {
    regFile.setPc(resetVector);

    // cop0.init();

    info("   [IOP       ] Successfully initialized.", .{});
}

/// Translates virtual address to physical address
fn translateAddr(addr: u32) u32 {
    // NOTE: this is Kernel mode only!

    var data: u32 = undefined;

    switch (@truncate(u4, addr >> 28)) {
        0x8 ... 0x9, 0xA ... 0xB => {
            data = addr & 0x1FFF_FFFF;
        },
        0x0 ... 0x7, 0xC ... 0xF => {
            err("  [IOP       ] Unhandled TLB mapped access @ 0x{X:0>8}.", .{addr});

            assert(false);
        },
    }

    return data;
}

/// Reads data from the system bus
fn read(comptime T: type, addr: u32) T {
    return bus.readIop(T, translateAddr(addr));
}

/// Fetches an instruction from memory and increments PC
fn fetchInstr() u32 {
    const instr = read(u32, regFile.pc);

    regFile.stepPc();

    return instr;
}

/// Writes data to the system bus
fn write(comptime T: type, addr: u32, data: T) void {
    bus.writeIop(T, translateAddr(addr), data);
}

/// Get Opcode field
fn getOpcode(instr: u32) u6 {
    return @truncate(u6, instr >> 26);
}

/// Get Funct field
fn getFunct(instr: u32) u6 {
    return @truncate(u6, instr);
}

/// Get 16-bit immediate
fn getImm16(instr: u32) u16 {
    return @truncate(u16, instr);
}

/// Get 26-bit offset
fn getInstrIndex(instr: u32) u26 {
    return @truncate(u26, instr);
}

/// Get Sa field
fn getSa(instr: u32) u5 {
    return @truncate(u5, instr >> 6);
}

/// Get Rd field
fn getRd(instr: u32) u5 {
    return @truncate(u5, instr >> 11);
}

/// Get Rs field
fn getRs(instr: u32) u5 {
    return @truncate(u5, instr >> 21);
}

/// Get Rt field
fn getRt(instr: u32) u5 {
    return @truncate(u5, instr >> 16);
}

/// Decodes and executes instructions
fn decodeInstr(instr: u32) void {
    const opcode = getOpcode(instr);

    switch (opcode) {
        @enumToInt(Opcode.Special) => {
            const funct = getFunct(instr);

            switch (funct) {
                @enumToInt(Special.Sll) => iSll(instr),
                @enumToInt(Special.Jr ) => iJr(instr),
                else => {
                    err("  [IOP       ] Unhandled SPECIAL instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Bne ) => iBne(instr),
        @enumToInt(Opcode.Slti) => iSlti(instr),
        @enumToInt(Opcode.Ori ) => iOri(instr),
        @enumToInt(Opcode.Lui ) => iLui(instr),
        @enumToInt(Opcode.Cop0) => {
            const rs = getRs(instr);

            switch (rs) {
                @enumToInt(CopOpcode.Mf) => iMfc(instr, 0),
                else => {
                    err("  [IOP       ] Unhandled COP0 instruction 0x{X} (0x{X:0>8}).", .{rs, instr});

                    assert(false);
                }
            }
        },
        else => {
            err("  [IOP       ] Unhandled instruction 0x{X} (0x{X:0>8}).", .{opcode, instr});

            assert(false);
        }
    }
}

/// Branch helper
fn doBranch(target: u32, isCond: bool, rd: u5) void {
    regFile.set(rd, regFile.npc);

    inDelaySlot[1] = true;

    if (isCond) {
        regFile.npc = target;
    }
}

/// Branch on Not Equal
fn iBne(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);
    const rt = getRt(instr);

    const target = regFile.pc +% offset;

    doBranch(target, regFile.get(rs) != regFile.get(rt), @enumToInt(CpuReg.R0));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        
        info("   [IOP       ] BNE ${s}, ${s}, 0x{X:0>8}; ${s} = 0x{X:0>8}, ${s} = 0x{X:0>8}", .{tagRs, tagRt, target, tagRs, regFile.get(rs), tagRt, regFile.get(rt)});
    }
}

/// Jump Register
fn iJr(instr: u32) void {
    const rs = getRs(instr);

    const target = regFile.get(rs);

    doBranch(target, true, 0);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
    
        info("   [EE Core   ] JR ${s}; PC = {X:0>8}h", .{tagRs, target});
    }
}

/// Load Upper Immediate
fn iLui(instr: u32) void {
    const imm16 = getImm16(instr);

    const rt = getRt(instr);

    regFile.set(rt, @as(u32, imm16) << 16);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] LUI ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, imm16, tagRt, regFile.get(rt)});
    }
}

/// Move From Coprocessor
fn iMfc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    //if (!cop0.isCopUsable(n)) {
    //    err("  [IOP       ] Coprocessor {} is unusable!", .{n});
    //
    //    assert(false);
    //}

    var data: u32 = undefined;

    switch (n) {
        0 => data = cop0.get(rd),
        else => {
            err("  [IOP       ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    regFile.set(rt, data);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [IOP       ] MFC{} ${s}, ${}; ${s} = 0x{X:0>8}", .{n, tagRt, rd, tagRt, regFile.get(rt)});
    }
}

/// OR Immediate
fn iOri(instr: u32) void {
    const imm16 = getImm16(instr);

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rt, regFile.get(rs) | @as(u32, imm16));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] ORI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, tagRs, imm16, tagRt, regFile.get(rt)});
    }
}

/// Shift Left Logical
fn iSll(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(rd, regFile.get(rt) << sa);

    if (doDisasm) {
        if (@intToEnum(CpuReg, rd) == CpuReg.R0) {
            info("   [IOP       ] NOP", .{});
        } else {
            const tagRd = @tagName(@intToEnum(CpuReg, rd));
            const tagRt = @tagName(@intToEnum(CpuReg, rt));

            info("   [IOP       ] SLL ${s}, ${s}, {}; ${s} = 0x{X:0>8}", .{tagRd, tagRt, sa, tagRd, regFile.get(rd)});
        }
    }
}

/// Set Less Than Immediate
fn iSlti(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rt, @as(u32, @bitCast(u1, @bitCast(i32, regFile.get(rs)) < @bitCast(i32, imm16s))));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SLTI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(rt)});
    }
}

/// Steps the IOP interpreter
pub fn step() void {
    regFile.cpc = regFile.pc;

    inDelaySlot[0] = inDelaySlot[1];
    inDelaySlot[1] = false;

    decodeInstr(fetchInstr());
}
