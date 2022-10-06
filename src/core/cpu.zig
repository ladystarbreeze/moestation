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

const cop0 = @import("cop0.zig");

const Cop0Reg = cop0.Cop0Reg;

const exts = @import("../common/extend.zig").exts;

/// Enable/disable disassembler
const doDisasm = true;

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
    Addiu   = 0x09,
    Slti    = 0x0A,
    Ori     = 0x0D,
    Lui     = 0x0F,
    Cop0    = 0x10,
    Sw      = 0x2B,
    Sd      = 0x3F,
};

/// SPECIAL instructions
const Special = enum(u6) {
    Sll  = 0x00,
    Jr   = 0x08,
    Jalr = 0x09,
    Sync = 0x0F,
};

/// COP instructions
const CopOpcode = enum(u5) {
    Mf = 0x00,
    Mt = 0x04,
    Co = 0x10,
};

/// COP Control instructions
const ControlOpcode = enum(u6) {
    Tlbwi = 0x02,
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
            else => unreachable,
        }

        return data;
    }

    /// Sets GPR
    pub fn set(self: *Gpr, comptime T: type, data: T) void {
        assert(T == u32 or T == u64 or T == u128);

        switch (T) {
            u32  => self.lo = exts(u64, u32, data),
            u64  => self.lo = data,
            u128 => {
                self.lo = @truncate(u64, data);
                self.hi = @truncate(u64, data >> 64);
            },
            else => unreachable,
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
    pub fn set(self: *RegFile, comptime T: type, idx: u5, data: T) void {
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

    cop0.init();

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
                @enumToInt(Special.Sll ) => iSll(instr),
                @enumToInt(Special.Jr  ) => iJr(instr),
                @enumToInt(Special.Jalr) => iJalr(instr),
                @enumToInt(Special.Sync) => iSync(instr),
                else => {
                    err("  [EE Core   ] Unhandled SPECIAL instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Bne  ) => iBne(instr),
        @enumToInt(Opcode.Addiu) => iAddiu(instr),
        @enumToInt(Opcode.Slti ) => iSlti(instr),
        @enumToInt(Opcode.Ori  ) => iOri(instr),
        @enumToInt(Opcode.Lui  ) => iLui(instr),
        @enumToInt(Opcode.Cop0 ) => {
            const rs = getRs(instr);

            switch (rs) {
                @enumToInt(CopOpcode.Mf) => iMfc(instr, 0),
                @enumToInt(CopOpcode.Mt) => iMtc(instr, 0),
                @enumToInt(CopOpcode.Co) => {
                    const funct = getFunct(instr);

                    switch (funct) {
                        @enumToInt(ControlOpcode.Tlbwi) => iTlbwi(),
                        else => {
                            err("  [EE Core   ] Unhandled COP0 Control instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                            assert(false);
                        }
                    }
                },
                else => {
                    err("  [EE Core   ] Unhandled COP0 instruction 0x{X} (0x{X:0>8}).", .{rs, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Sw) => iSw(instr),
        @enumToInt(Opcode.Sd) => iSd(instr),
        else => {
            err("  [EE Core   ] Unhandled instruction 0x{X} (0x{X:0>8}).", .{opcode, instr});

            assert(false);
        }
    }
}

/// Branch helper
fn doBranch(target: u32, isCond: bool, rd: u5, comptime isLikely: bool) void {
    regFile.set(u64, rd, @as(u64, regFile.npc));

    if (isCond) {
        regFile.npc = target;

        inDelaySlot[1] = true;
    } else {
        if (isLikely) {
            regFile.setPc(regFile.npc);
        } else {
            inDelaySlot[1] = true;
        }
    }
}

/// ADD Immediate Unsigned
fn iAddiu(instr: u32) void {
    const imm16s = exts(u64, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rt, @truncate(u32, regFile.get(u64, rs) +% imm16s));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] ADDIU ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(u64, rt)});
    }
}

/// Branch on Not Equal
fn iBne(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);
    const rt = getRt(instr);

    const target = regFile.pc +% offset;

    doBranch(target, regFile.get(u64, rs) != regFile.get(u64, rt), @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        
        info("   [EE Core   ] BNE ${s}, ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}, ${s} = 0x{X:0>16}", .{tagRs, tagRt, target, tagRs, regFile.get(u64, rs), tagRt, regFile.get(u64, rt)});
    }
}

/// Jump And Link Register
fn iJalr(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);

    const target = regFile.get(u32, rs);

    doBranch(target, true, rd, false);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
    
        info("   [EE Core   ] JALR ${s}, ${s}; ${s} = 0x{X:0>8}, PC = {X:0>8}h", .{tagRd, tagRs, tagRd, regFile.get(u32, rd), target});
    }
}

/// Jump Register
fn iJr(instr: u32) void {
    const rs = getRs(instr);

    const target = regFile.get(u32, rs);

    doBranch(target, true, 0, false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
    
        info("   [EE Core   ] JR ${s}; PC = {X:0>8}h", .{tagRs, target});
    }
}

/// Load Upper Immediate
fn iLui(instr: u32) void {
    const imm16 = getImm16(instr);

    const rt = getRt(instr);

    regFile.set(u32, rt, @as(u32, imm16) << 16);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LUI ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, imm16, tagRt, regFile.get(u64, rt)});
    }
}

/// Move From Coprocessor
fn iMfc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    var data: u32 = undefined;

    switch (n) {
        0 => data = cop0.get(u32, rd),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    regFile.set(u32, rt, data);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        const tagRd = @tagName(@intToEnum(Cop0Reg, rd));
    
        info("   [EE Core   ] MFC{} ${s}, ${s}; ${s} = 0x{X:0>8}", .{n, tagRt, tagRd, tagRt, regFile.get(u32, rt)});
    }
}

/// Move To Coprocessor
fn iMtc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    const data = regFile.get(u32, rt);

    switch (n) {
        0 => cop0.set(u32, rd, data),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        const tagRd = @tagName(@intToEnum(Cop0Reg, rd));
    
        info("   [EE Core   ] MTC{} ${s}, ${s}; ${s} = 0x{X:0>8}", .{n, tagRt, tagRd, tagRd, regFile.get(u32, rt)});
    }
}

/// OR Immediate
fn iOri(instr: u32) void {
    const imm16 = getImm16(instr);

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rt, regFile.get(u64, rs) | @as(u64, imm16));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] ORI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16, tagRt, regFile.get(u64, rt)});
    }
}

/// Store Doubleword
fn iSd(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const data = regFile.get(u64, rt);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SD ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, addr, data});
    }

    if ((addr & 7) != 0) {
        err("  [EE Core   ] Unhandled AdES @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    write(u64, addr, data);
}

/// Shift Left Logical
fn iSll(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, regFile.get(u32, rt) << sa);

    if (doDisasm) {
        if (@intToEnum(CpuReg, rd) == CpuReg.R0) {
            info("   [EE Core   ] NOP", .{});
        } else {
            const tagRd = @tagName(@intToEnum(CpuReg, rd));
            const tagRt = @tagName(@intToEnum(CpuReg, rt));

            info("   [EE Core   ] SLL ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
        }
    }
}

/// Set Less Than Immediate
fn iSlti(instr: u32) void {
    const imm16s = exts(u64, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rt, @as(u64, @bitCast(u1, @bitCast(i64, regFile.get(u64, rs)) < @bitCast(i64, imm16s))));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SLTI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(u64, rt)});
    }
}

/// Store Word
fn iSw(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const data = regFile.get(u32, rt);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SW ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, addr, data});
    }

    if ((addr & 3) != 0) {
        err("  [EE Core   ] Unhandled AdES @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    write(u32, addr, data);
}

/// Synchronize
fn iSync(instr: u32) void {
    const stype = getSa(instr);

    if (doDisasm) {
        const syncType = if ((stype >> 4) != 0) "P" else "L";

        info("   [EE Core   ] SYNC.{s}", .{syncType});
    }
}

/// TLB Write Indexed
fn iTlbwi() void {
    if (doDisasm) {
        info("   [EE Core   ] TLBWI", .{});
    }

    cop0.setEntryIndexed();
}

/// Steps the EE Core interpreter
pub fn step() void {
    regFile.cpc = regFile.pc;

    inDelaySlot[0] = inDelaySlot[1];
    inDelaySlot[1] = false;

    decodeInstr(fetchInstr());
}
