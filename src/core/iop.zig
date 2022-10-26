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
    Regimm  = 0x01,
    J       = 0x02,
    Jal     = 0x03,
    Beq     = 0x04,
    Bne     = 0x05,
    Blez    = 0x06,
    Bgtz    = 0x07,
    Addi    = 0x08,
    Addiu   = 0x09,
    Slti    = 0x0A,
    Sltiu   = 0x0B,
    Andi    = 0x0C,
    Ori     = 0x0D,
    Lui     = 0x0F,
    Cop0    = 0x10,
    Lb      = 0x20,
    Lh      = 0x21,
    Lw      = 0x23,
    Lbu     = 0x24,
    Lhu     = 0x25,
    Sb      = 0x28,
    Sh      = 0x29,
    Sw      = 0x2B,
};

/// SPECIAL instructions
const Special = enum(u6) {
    Sll   = 0x00,
    Srl   = 0x02,
    Sra   = 0x03,
    Jr    = 0x08,
    Jalr  = 0x09,
    Mflo  = 0x12,
    Div   = 0x1A,
    Divu  = 0x1B,
    Add   = 0x20,
    Addu  = 0x21,
    Subu  = 0x23,
    And   = 0x24,
    Or    = 0x25,
    Sltu  = 0x2B,
};

/// REGIMM instructions
const Regimm = enum(u5) {
    Bltz = 0x00,
    Bgez = 0x01,
};

/// COP instructions
const CopOpcode = enum(u5) {
    Mf = 0x00,
    Mt = 0x04,
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
    return addr & 0x1FFF_FFFF;
}

/// Reads data from the system bus
fn read(comptime T: type, addr: u32, comptime isData: bool) T {
    if (isData and cop0.isCacheIsolated()) {
        err("  [IOP       ] Cache is isolated!", .{});

        assert(false);
    }

    return bus.readIop(T, translateAddr(addr));
}

/// Fetches an instruction from memory and increments PC
fn fetchInstr() u32 {
    const instr = read(u32, regFile.pc, false);

    regFile.stepPc();

    return instr;
}

/// Writes data to the system bus
fn write(comptime T: type, addr: u32, data: T) void {
    if (cop0.isCacheIsolated()) {
        return info("   [IOP       ] Cache is isolated!", .{});
    }

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
                @enumToInt(Special.Sll ) => iSll(instr),
                @enumToInt(Special.Srl ) => iSrl(instr),
                @enumToInt(Special.Sra ) => iSra(instr),
                @enumToInt(Special.Jr  ) => iJr(instr),
                @enumToInt(Special.Jalr) => iJalr(instr),
                @enumToInt(Special.Mflo) => iMflo(instr),
                @enumToInt(Special.Div ) => iDiv(instr),
                @enumToInt(Special.Divu) => iDivu(instr),
                @enumToInt(Special.Add ) => iAdd(instr),
                @enumToInt(Special.Addu) => iAddu(instr),
                @enumToInt(Special.Subu) => iSubu(instr),
                @enumToInt(Special.And ) => iAnd(instr),
                @enumToInt(Special.Or  ) => iOr(instr),
                @enumToInt(Special.Sltu) => iSltu(instr),
                else => {
                    err("  [IOP       ] Unhandled SPECIAL instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Regimm) => {
            const rt = getRt(instr);

            switch (rt) {
                @enumToInt(Regimm.Bltz) => iBltz(instr),
                @enumToInt(Regimm.Bgez) => iBgez(instr),
                else => {
                    err("  [IOP       ] Unhandled REGIMM instruction 0x{X} (0x{X:0>8}).", .{rt, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.J    ) => iJ(instr),
        @enumToInt(Opcode.Jal  ) => iJal(instr),
        @enumToInt(Opcode.Beq  ) => iBeq(instr),
        @enumToInt(Opcode.Bne  ) => iBne(instr),
        @enumToInt(Opcode.Blez ) => iBlez(instr),
        @enumToInt(Opcode.Bgtz ) => iBgtz(instr),
        @enumToInt(Opcode.Addi ) => iAddi(instr),
        @enumToInt(Opcode.Addiu) => iAddiu(instr),
        @enumToInt(Opcode.Slti ) => iSlti(instr),
        @enumToInt(Opcode.Sltiu) => iSltiu(instr),
        @enumToInt(Opcode.Andi ) => iAndi(instr),
        @enumToInt(Opcode.Ori  ) => iOri(instr),
        @enumToInt(Opcode.Lui  ) => iLui(instr),
        @enumToInt(Opcode.Cop0 ) => {
            const rs = getRs(instr);

            switch (rs) {
                @enumToInt(CopOpcode.Mf) => iMfc(instr, 0),
                @enumToInt(CopOpcode.Mt) => iMtc(instr, 0),
                else => {
                    err("  [IOP       ] Unhandled COP0 instruction 0x{X} (0x{X:0>8}).", .{rs, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Lb ) => iLb(instr),
        @enumToInt(Opcode.Lh ) => iLh(instr),
        @enumToInt(Opcode.Lw ) => iLw(instr),
        @enumToInt(Opcode.Lbu) => iLbu(instr),
        @enumToInt(Opcode.Lhu) => iLhu(instr),
        @enumToInt(Opcode.Sb ) => iSb(instr),
        @enumToInt(Opcode.Sh ) => iSh(instr),
        @enumToInt(Opcode.Sw ) => iSw(instr),
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

/// ADD
fn iAdd(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    var res: i32 = undefined;

    if (@addWithOverflow(i32, @bitCast(i32, regFile.get(rs)), @bitCast(i32, regFile.get(rt)), &res)) {
        err("  [IOP       ] Unhandled arithmetic overflow exception.", .{});

        assert(false);
    }

    regFile.set(rd, @bitCast(u32, res));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] ADD ${s}, ${s}, ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(rd)});
    }
}

/// ADD Immediate
fn iAddi(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    var res: i32 = undefined;

    if (@addWithOverflow(i32, @bitCast(i32, regFile.get(rs)), @bitCast(i32, imm16s), &res)) {
        err("  [IOP       ] Unhandled arithmetic overflow exception.", .{});

        assert(false);
    }

    regFile.set(rt, @bitCast(u32, res));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] ADDI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(rt)});
    }
}

/// ADD Immediate Unsigned
fn iAddiu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rt, regFile.get(rs) +% imm16s);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] ADDIU ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(rt)});
    }
}

/// ADD Unsigned
fn iAddu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rd, regFile.get(rs) +% regFile.get(rt));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] ADDU ${s}, ${s}, ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(rd)});
    }
}

/// AND
fn iAnd(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(rs) & regFile.get(rt);

    regFile.set(rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] AND ${s}, ${s}, ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// AND Immediate
fn iAndi(instr: u32) void {
    const imm16 = getImm16(instr);

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rt, regFile.get(rs) & @as(u32, imm16));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] ANDI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, tagRs, imm16, tagRt, regFile.get(rt)});
    }
}

/// Branch on EQual
fn iBeq(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);
    const rt = getRt(instr);

    const target = regFile.pc +% offset;

    doBranch(target, regFile.get(rs) == regFile.get(rt), @enumToInt(CpuReg.R0));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        
        info("   [IOP       ] BEQ ${s}, ${s}, 0x{X:0>8}; ${s} = 0x{X:0>8}, ${s} = 0x{X:0>8}", .{tagRs, tagRt, target, tagRs, regFile.get(rs), tagRt, regFile.get(rt)});
    }
}

/// Branch on Greater than or Equal Zero
fn iBgez(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i32, regFile.get(rs)) >= 0, @enumToInt(CpuReg.R0));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [IOP       ] BGEZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(rs)});
    }
}

/// Branch on Greater Than Zero
fn iBgtz(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i32, regFile.get(rs)) > 0, @enumToInt(CpuReg.R0));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [IOP       ] BGTZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(rs)});
    }
}

/// Branch on Less than or Equal Zero
fn iBlez(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i32, regFile.get(rs)) <= 0, @enumToInt(CpuReg.R0));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [IOP       ] BLEZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(rs)});
    }
}

/// Branch on Less Than Zero
fn iBltz(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i32, regFile.get(rs)) < 0, @enumToInt(CpuReg.R0));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [IOP       ] BLTZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(rs)});
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

/// DIVide
fn iDiv(instr: u32) void {
    const rs = getRs(instr);
    const rt = getRt(instr);

    const n = @bitCast(i32, regFile.get(rs));
    const d = @bitCast(i32, regFile.get(rt));

    assert(d != 0);
    assert(!(n == -0x80000000 and d == -1));

    regFile.lo = @bitCast(u32, @divFloor(n, d));

    if (d < 0) {
        regFile.hi = @bitCast(u32, @rem(n, -d));
    } else {
        regFile.hi = @bitCast(u32, n) % @bitCast(u32, d);
    }

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] DIV ${s}, ${s}; LO = 0x{X:0>8}, HI = 0x{X:0>8}", .{tagRs, tagRt, regFile.lo, regFile.hi});
    }
}

/// DIVide Unsigned
fn iDivu(instr: u32) void {
    const rs = getRs(instr);
    const rt = getRt(instr);

    const n = regFile.get(rs);
    const d = regFile.get(rt);

    assert(d != 0);

    regFile.lo = n / d;
    regFile.hi = n % d;

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] DIVU ${s}, ${s}; LO = 0x{X:0>8}, HI = 0x{X:0>8}", .{tagRs, tagRt, regFile.lo, regFile.hi});
    }
}

/// Jump
fn iJ(instr: u32) void {
    const target = (regFile.pc & 0xF000_0000) | (@as(u32, getInstrIndex(instr)) << 2);

    doBranch(target, true, @enumToInt(CpuReg.R0));

    if (doDisasm) {
        info("   [IOP       ] J 0x{X:0>8}; PC = {X:0>8}h", .{target, target});
    }
}

/// Jump And Link
fn iJal(instr: u32) void {
    const target = (regFile.pc & 0xF000_0000) | (@as(u32, getInstrIndex(instr)) << 2);

    doBranch(target, true, @enumToInt(CpuReg.RA));

    if (doDisasm) {
        info("   [IOP       ] JAL 0x{X:0>8}; $RA = 0x{X:0>8}, PC = {X:0>8}h", .{target, regFile.get(@enumToInt(CpuReg.RA)), target});
    }
}

/// Jump And Link Register
fn iJalr(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);

    const target = regFile.get(rs);

    doBranch(target, true, rd);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
    
        info("   [IOP       ] JAL ${s}, ${s}; ${s} = 0x{X:0>8}, PC = {X:0>8}h", .{tagRd, tagRs, tagRd, regFile.get(rd), target});
    }
}

/// Jump Register
fn iJr(instr: u32) void {
    const rs = getRs(instr);

    const target = regFile.get(rs);

    doBranch(target, true, 0);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
    
        info("   [IOP       ] JR ${s}; PC = {X:0>8}h", .{tagRs, target});
    }
}

/// Load Byte
fn iLb(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;

    const data = exts(u32, u8, read(u8, addr, true));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] LB ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(rt, data);
}

/// Load Byte Unsigned
fn iLbu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;

    const data = read(u8, addr, true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] LBU ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(rt, @as(u32, data));
}

/// Load Halfword
fn iLh(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;

    if ((addr & 1) != 0) {
        err("  [IOP       ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = exts(u32, u16, read(u16, addr, true));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] LH ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(rt, data);
}

/// Load Halfword Unsigned
fn iLhu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;

    if ((addr & 1) != 0) {
        err("  [IOP       ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = read(u16, addr, true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] LH ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(rt, @as(u32, data));
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

/// Load Word
fn iLw(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;

    if ((addr & 3) != 0) {
        err("  [IOP       ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = read(u32, addr, true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] LW ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(rt, data);
}

/// Move From Coprocessor
fn iMfc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    if (!cop0.isCopUsable(n)) {
        err("  [IOP       ] Coprocessor {} is unusable!", .{n});
    
        assert(false);
    }

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

/// Move From LO
fn iMflo(instr: u32) void {
    const rd = getRd(instr);

    regFile.set(rd, regFile.lo);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));

        info("   [IOP       ] MFLO ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRd, regFile.get(rd)});
    }
}

/// Move To Coprocessor
fn iMtc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    if (!cop0.isCopUsable(n)) {
        err("  [IOP       ] Coprocessor {} is unusable!", .{n});
    
        assert(false);
    }

    const data = regFile.get(rt);

    switch (n) {
        0 => cop0.set(rd, data),
        else => {
            err("  [IOP       ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [IOP       ] MTC{} ${s}, ${}; ${} = 0x{X:0>8}", .{n, tagRt, rd, rd, data});
    }
}

/// OR
fn iOr(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(rs) | regFile.get(rt);

    regFile.set(rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] OR ${s}, ${s}, ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRs, tagRt, tagRd, res});
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

/// Store Byte
fn iSb(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;
    const data = @truncate(u8, regFile.get(rt));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SB ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>2}", .{tagRt, imm16s, tagRs, addr, data});
    }

    write(u8, addr, data);
}

/// Store Halfword
fn iSh(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;
    const data = @truncate(u16, regFile.get(rt));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SH ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>4}", .{tagRt, imm16s, tagRs, addr, data});
    }

    if ((addr & 1) != 0) {
        err("  [IOP       ] Unhandled AdES @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    write(u16, addr, data);
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

/// Set Less Than Immediate Unsigned
fn iSltiu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rt, @as(u32, @bitCast(u1, regFile.get(rs) < imm16s)));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SLTIU ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>8}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(rt)});
    }
}

/// Set Less Than Unsigned
fn iSltu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rd, @as(u32, @bitCast(u1, regFile.get(rs) < regFile.get(rt))));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SLTU ${s}, ${s}, ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(rd)});
    }
}

/// Shift Right Arithmetic
fn iSra(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(rd, @bitCast(u32, @bitCast(i32, regFile.get(rt)) >> sa));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SRA ${s}, ${s}, {}; ${s} = 0x{X:0>8}", .{tagRd, tagRt, sa, tagRd, regFile.get(rd)});
    }
}

/// Shift Right Logical
fn iSrl(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(rd, regFile.get(rt) >> sa);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SRL ${s}, ${s}, {}; ${s} = 0x{X:0>8}", .{tagRd, tagRt, sa, tagRd, regFile.get(rd)});
    }
}

/// SUBtract Unsigned
fn iSubu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(rd, regFile.get(rs) -% regFile.get(rt));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SUBU ${s}, ${s}, ${s}; ${s} = 0x{X:0>8}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(rd)});
    }
}

/// Store Word
fn iSw(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(rs) +% imm16s;
    const data = regFile.get(rt);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [IOP       ] SW ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>8}", .{tagRt, imm16s, tagRs, addr, data});
    }

    if ((addr & 3) != 0) {
        err("  [IOP       ] Unhandled AdES @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    write(u32, addr, data);
}

/// Steps the IOP interpreter
pub fn step() void {
    regFile.cpc = regFile.pc;

    if (regFile.cpc == 0x12C48 or regFile.cpc == 0x1420C or regFile.cpc == 0x1430C) {
        assert(false);
    }

    inDelaySlot[0] = inDelaySlot[1];
    inDelaySlot[1] = false;

    decodeInstr(fetchInstr());
}
