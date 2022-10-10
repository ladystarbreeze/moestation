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

const cop1 = @import("cop1.zig");

const exts = @import("../common/extend.zig").exts;

/// Enable/disable disassembler
const doDisasm = false;

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
    Addiu   = 0x09,
    Slti    = 0x0A,
    Sltiu   = 0x0B,
    Andi    = 0x0C,
    Ori     = 0x0D,
    Xori    = 0x0E,
    Lui     = 0x0F,
    Cop0    = 0x10,
    Beql    = 0x14,
    Bnel    = 0x15,
    Mmi     = 0x1C,
    Lb      = 0x20,
    Lw      = 0x23,
    Lbu     = 0x24,
    Lhu     = 0x25,
    Sb      = 0x28,
    Sh      = 0x29,
    Sw      = 0x2B,
    Ld      = 0x37,
    Swc1    = 0x39,
    Sd      = 0x3F,
};

/// SPECIAL instructions
const Special = enum(u6) {
    Sll    = 0x00,
    Srl    = 0x02,
    Sra    = 0x03,
    Jr     = 0x08,
    Jalr   = 0x09,
    Movz   = 0x0A,
    Movn   = 0x0B,
    Sync   = 0x0F,
    Mfhi   = 0x10,
    Mflo   = 0x12,
    Dsrav  = 0x17,
    Mult   = 0x18,
    Div    = 0x1A,
    Divu   = 0x1B,
    Addu   = 0x21,
    Subu   = 0x23,
    And    = 0x24,
    Or     = 0x25,
    Slt    = 0x2A,
    Sltu   = 0x2B,
    Daddu  = 0x2D,
    Dsll32 = 0x3C,
    Dsra32 = 0x3F,
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
    Co = 0x10,
};

/// COP Control instructions
const ControlOpcode = enum(u6) {
    Tlbwi = 0x02,
};

/// MMI instructions
const MmiOpcode = enum(u6) {
    Mflo1 = 0x12,
    Mult1 = 0x18,
    Divu1 = 0x1B,
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

    /// Returns high 64 bits of GPR (for LO/HI)
    pub fn getHi(self: Gpr, comptime T: type) T {
        assert(T == u32 or T == u64);

        var data: T = undefined;

        switch (T) {
            u32  => data = @truncate(u32, self.hi),
            u64  => data = self.hi,
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

    /// Sets high 64 bits of GPR (for LO/HI)
    pub fn setHi(self: *Gpr, comptime T: type, data: T) void {
        assert(T == u32 or T == u64);

        switch (T) {
            u32  => self.hi = exts(u64, u32, data),
            u64  => self.hi = data,
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

    lo: Gpr = undefined,
    hi: Gpr = undefined,

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

/// Scratchpad RAM
var spram: [0x4000]u8 = undefined;

/// Initializes the EE Core interpreter
pub fn init() void {
    regFile.setPc(resetVector);

    cop0.init();

    info("   [EE Core   ] Successfully initialized.", .{});
}

/// Translates virtual address to physical address. Returns true if scratchpad access
fn translateAddr(comptime isWrite: bool, addr: *u32) bool {
    // NOTE: this is Kernel mode only!
    var isScratchpad = false;

    switch (@truncate(u4, addr.* >> 28)) {
        0x8 ... 0x9, 0xA ... 0xB => {
            addr.* &= 0x1FFF_FFFF;
        },
        0x0 ... 0x7, 0xC ... 0xF => {
            isScratchpad = cop0.translateAddrTlb(isWrite, addr);
        },
    }

    return isScratchpad;
}

/// Reads data from the system bus
fn read(comptime T: type, addr: u32) T {
    var pAddr = addr;

    const isScratchpad = translateAddr(false, &pAddr);

    if (isScratchpad) {
        return readSpram(T, pAddr);
    }

    return bus.read(T, pAddr);
}

/// Reads data from scratchpad RAM
fn readSpram(comptime T: type, addr: u32) T {
    var data: T = undefined;

    @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &spram[addr]), @sizeOf(T));

    return data;
}

/// Fetches an instruction from memory and increments PC
fn fetchInstr() u32 {
    const instr = read(u32, regFile.pc);

    regFile.stepPc();

    return instr;
}

/// Writes data to the system bus
fn write(comptime T: type, addr: u32, data: T) void {
    var pAddr = addr;

    const isScratchpad = translateAddr(true, &pAddr);

    if (isScratchpad) {
        return writeSpram(T, pAddr, data);
    }

    bus.write(T, pAddr, data);
}

/// Writes data to scratchpad RAM
fn writeSpram(comptime T: type, addr: u32, data: T) void {
    @memcpy(@ptrCast([*]u8, &spram[addr]), @ptrCast([*]const u8, &data), @sizeOf(T));
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
                @enumToInt(Special.Sll   ) => iSll(instr),
                @enumToInt(Special.Srl   ) => iSrl(instr),
                @enumToInt(Special.Sra   ) => iSra(instr),
                @enumToInt(Special.Jr    ) => iJr(instr),
                @enumToInt(Special.Jalr  ) => iJalr(instr),
                @enumToInt(Special.Movz  ) => iMovz(instr),
                @enumToInt(Special.Movn  ) => iMovn(instr),
                @enumToInt(Special.Sync  ) => iSync(instr),
                @enumToInt(Special.Mfhi  ) => iMfhi(instr, false),
                @enumToInt(Special.Mflo  ) => iMflo(instr, false),
                @enumToInt(Special.Dsrav ) => iDsrav(instr),
                @enumToInt(Special.Mult  ) => iMult(instr, 0),
                @enumToInt(Special.Div   ) => iDiv(instr),
                @enumToInt(Special.Divu  ) => iDivu(instr, 0),
                @enumToInt(Special.Addu  ) => iAddu(instr),
                @enumToInt(Special.Subu  ) => iSubu(instr),
                @enumToInt(Special.And   ) => iAnd(instr),
                @enumToInt(Special.Or    ) => iOr(instr),
                @enumToInt(Special.Slt   ) => iSlt(instr),
                @enumToInt(Special.Sltu  ) => iSltu(instr),
                @enumToInt(Special.Daddu ) => iDaddu(instr),
                @enumToInt(Special.Dsll32) => iDsll32(instr),
                @enumToInt(Special.Dsra32) => iDsra32(instr),
                else => {
                    err("  [EE Core   ] Unhandled SPECIAL instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

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
                    err("  [EE Core   ] Unhandled REGIMM instruction 0x{X} (0x{X:0>8}).", .{rt, instr});

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
        @enumToInt(Opcode.Addiu) => iAddiu(instr),
        @enumToInt(Opcode.Slti ) => iSlti(instr),
        @enumToInt(Opcode.Sltiu) => iSltiu(instr),
        @enumToInt(Opcode.Andi ) => iAndi(instr),
        @enumToInt(Opcode.Ori  ) => iOri(instr),
        @enumToInt(Opcode.Xori ) => iXori(instr),
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
        @enumToInt(Opcode.Beql) => iBeql(instr),
        @enumToInt(Opcode.Bnel) => iBnel(instr),
        @enumToInt(Opcode.Mmi ) => {
            const funct = getFunct(instr);

            switch (funct) {
                @enumToInt(MmiOpcode.Mflo1) => iMflo(instr, true),
                @enumToInt(MmiOpcode.Mult1) => iMult(instr, 1),
                @enumToInt(MmiOpcode.Divu1) => iDivu(instr, 1),
                else => {
                    err("  [EE Core   ] Unhandled MMI instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Lb  ) => iLb(instr),
        @enumToInt(Opcode.Lw  ) => iLw(instr),
        @enumToInt(Opcode.Lbu ) => iLbu(instr),
        @enumToInt(Opcode.Lhu ) => iLhu(instr),
        @enumToInt(Opcode.Sb  ) => iSb(instr),
        @enumToInt(Opcode.Sh  ) => iSh(instr),
        @enumToInt(Opcode.Sw  ) => iSw(instr),
        @enumToInt(Opcode.Ld  ) => iLd(instr),
        @enumToInt(Opcode.Swc1) => iSwc(instr, 1),
        @enumToInt(Opcode.Sd  ) => iSd(instr),
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
        assert(target != 0xBFC00928);

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

/// ADD Unsigned
fn iAddu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, @truncate(u32, regFile.get(u64, rs) +% regFile.get(u64, rt)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] ADDU ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(u64, rd)});
    }
}

/// AND
fn iAnd(instr: u32) void {
    const rd = getRs(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(u64, rs) & regFile.get(u64, rt);

    regFile.set(u64, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] AND ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// AND Immediate
fn iAndi(instr: u32) void {
    const imm16 = getImm16(instr);

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rt, regFile.get(u64, rs) & @as(u64, imm16));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] ANDI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16, tagRt, regFile.get(u64, rt)});
    }
}

/// Branch on EQual
fn iBeq(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);
    const rt = getRt(instr);

    const target = regFile.pc +% offset;

    doBranch(target, regFile.get(u64, rs) == regFile.get(u64, rt), @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        
        info("   [EE Core   ] BEQ ${s}, ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}, ${s} = 0x{X:0>16}", .{tagRs, tagRt, target, tagRs, regFile.get(u64, rs), tagRt, regFile.get(u64, rt)});
    }
}

/// Branch on EQual Likely
fn iBeql(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);
    const rt = getRt(instr);

    const target = regFile.pc +% offset;

    doBranch(target, regFile.get(u64, rs) == regFile.get(u64, rt), @enumToInt(CpuReg.R0), true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        
        info("   [EE Core   ] BEQL ${s}, ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}, ${s} = 0x{X:0>16}", .{tagRs, tagRt, target, tagRs, regFile.get(u64, rs), tagRt, regFile.get(u64, rt)});
    }
}

/// Branch on Greater than or Equal Zero
fn iBgez(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) >= 0, @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BGEZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
    }
}

/// Branch on Greater Than Zero
fn iBgtz(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) > 0, @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BGTZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
    }
}

/// Branch on Less than or Equal Zero
fn iBlez(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) <= 0, @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BLEZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
    }
}

/// Branch on Less Than Zero
fn iBltz(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) < 0, @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BLTZ ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
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

/// Branch on Not Equal Likely
fn iBnel(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);
    const rt = getRt(instr);

    const target = regFile.pc +% offset;

    doBranch(target, regFile.get(u64, rs) != regFile.get(u64, rt), @enumToInt(CpuReg.R0), true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
        
        info("   [EE Core   ] BNEL ${s}, ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}, ${s} = 0x{X:0>16}", .{tagRs, tagRt, target, tagRs, regFile.get(u64, rs), tagRt, regFile.get(u64, rt)});
    }
}

/// Doubleword ADD Unsigned
fn iDaddu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(u64, rs) +% regFile.get(u64, rt);

    regFile.set(u64, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DADDU ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// DIVide
fn iDiv(instr: u32) void {
    const rs = getRs(instr);
    const rt = getRt(instr);

    const n = @bitCast(i32, regFile.get(u32, rs));
    const d = @bitCast(i32, regFile.get(u32, rt));

    assert(d != 0);
    assert(!(n == -0x80000000 and d == -1));

    regFile.lo.set(u32, @bitCast(u32, @divFloor(n, d)));

    if (d < 0) {
        regFile.hi.set(u32, @bitCast(u32, @rem(n, -d)));
    } else {
        regFile.hi.set(u32, @bitCast(u32, n) % @bitCast(u32, d));
    }

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DIV ${s}, ${s}; LO = 0x{X:0>16}, HI = 0x{X:0>16}", .{tagRs, tagRt, regFile.lo.get(u64), regFile.hi.get(u64)});
    }
}

/// DIVide Unsigned
fn iDivu(instr: u32, comptime pipeline: u1) void {
    const rs = getRs(instr);
    const rt = getRt(instr);

    const n = regFile.get(u32, rs);
    const d = regFile.get(u32, rt);

    assert(d != 0);

    const q = n / d;
    const r = n % d;

    if (pipeline == 1) {
        regFile.lo.setHi(u32, q);
        regFile.hi.setHi(u32, r);
    } else {
        regFile.lo.set(u32, q);
        regFile.hi.set(u32, r);
    }

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        const isPipe1 = if (pipeline == 1) "1" else "";

        info("   [EE Core   ] DIVU{s} ${s}, ${s}; LO = 0x{X:0>16}, HI = 0x{X:0>16}", .{isPipe1, tagRs, tagRt, regFile.lo.get(u64), regFile.hi.get(u64)});
    }
}

/// Doubleword Shift Left Logical + 32
fn iDsll32(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, regFile.get(u64, rt) << (@as(u6, sa) + 32));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSLL32 ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Doubleword Shift Right Arithmetic Variable
fn iDsrav(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, @bitCast(u64, @bitCast(i64, regFile.get(u64, rt)) >> @truncate(u6, regFile.get(u64, rs))));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSRAV ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, tagRs, tagRd, regFile.get(u64, rd)});
    }
}

/// Doubleword Shift Right Arithmetic
fn iDsra32(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, @bitCast(u64, @bitCast(i64, regFile.get(u64, rt)) >> (@as(u6, sa) + 32)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSRA32 ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Jump
fn iJ(instr: u32) void {
    const target = (regFile.pc & 0xF000_0000) | (@as(u32, getInstrIndex(instr)) << 2);

    doBranch(target, true, @enumToInt(CpuReg.R0), false);

    if (doDisasm) {
        info("   [EE Core   ] J 0x{X:0>8}; PC = {X:0>8}h", .{target, target});
    }
}

/// Jump And Link
fn iJal(instr: u32) void {
    const target = (regFile.pc & 0xF000_0000) | (@as(u32, getInstrIndex(instr)) << 2);

    doBranch(target, true, @enumToInt(CpuReg.RA), false);

    if (doDisasm) {
        info("   [EE Core   ] JAL 0x{X:0>8}; $RA = 0x{X:0>8}, PC = {X:0>8}h", .{target, regFile.get(u64, @enumToInt(CpuReg.RA)), target});
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
    
        info("   [EE Core   ] JALR ${s}, ${s}; ${s} = 0x{X:0>8}, PC = {X:0>8}h", .{tagRd, tagRs, tagRd, regFile.get(u64, rd), target});
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

/// Load Byte
fn iLb(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const data = exts(u64, u8, read(u8, addr));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LB ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
}

/// Load Byte Unsigned
fn iLbu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const data = @as(u64, read(u8, addr));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LBU ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
}

/// Load Doubleword
fn iLd(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if ((addr & 7) != 0) {
        err("  [EE Core   ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = read(u64, addr);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LD ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
}

/// Load Halfword Unsigned
fn iLhu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if ((addr & 1) != 0) {
        err("  [EE Core   ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = @as(u64, read(u16, addr));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LHU ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
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

/// Load Word
fn iLw(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if ((addr & 3) != 0) {
        err("  [EE Core   ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = exts(u64, u32, read(u32, addr));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LW ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
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

/// Move From HI
fn iMfhi(instr: u32, isHi: bool) void {
    const rd = getRd(instr);

    var data: u64 = undefined;
    
    if (isHi) {
        data = regFile.hi.getHi(u64);
    } else {
        data = regFile.hi.get(u64);
    }

    regFile.set(u64, rd, data);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));

        const is1 = if (isHi) "1" else "";

        info("   [EE Core   ] MFHI{s} ${s}; ${s} = 0x{X:0>16}", .{is1, tagRd, tagRd, data});
    }
}

/// Move From LO
fn iMflo(instr: u32, isHi: bool) void {
    const rd = getRd(instr);

    var data: u64 = undefined;
    
    if (isHi) {
        data = regFile.lo.getHi(u64);
    } else {
        data = regFile.lo.get(u64);
    }

    regFile.set(u64, rd, data);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));

        const is1 = if (isHi) "1" else "";

        info("   [EE Core   ] MFLO{s} ${s}; ${s} = 0x{X:0>16}", .{is1, tagRd, tagRd, data});
    }
}

/// MOVe on Not equal
fn iMovn(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    if (regFile.get(u64, rt) != 0) {
        regFile.set(u64, rd, regFile.get(u64, rs));
    }

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] MOVN ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRt, regFile.get(u64, rd)});
    }
}

/// MOVe on Zero
fn iMovz(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    if (regFile.get(u64, rt) == 0) {
        regFile.set(u64, rd, regFile.get(u64, rs));
    }

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] MOVZ ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(u64, rd)});
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

/// MULTiply
fn iMult(instr: u32, comptime pipeline: u1) void {
    const rd = getRs(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = @intCast(i64, @bitCast(i32, regFile.get(u32, rs))) *% @intCast(i64, @bitCast(i32, regFile.get(u32, rt)));

    if (pipeline == 1) {
        regFile.lo.setHi(u32, @truncate(u32, @bitCast(u64, res)));
        regFile.hi.setHi(u32, @truncate(u32, @bitCast(u64, res) >> 32));
    } else {
        regFile.lo.set(u32, @truncate(u32, @bitCast(u64, res)));
        regFile.hi.set(u32, @truncate(u32, @bitCast(u64, res) >> 32));
    }

    regFile.set(u32, rd, @truncate(u32, @bitCast(u64, res)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        const isPipe1 = if (pipeline == 1) "1" else "";

        if (rd == 0) {
            info("   [EE Core   ] MULT{s} ${s}, ${s}; LO = 0x{X:0>16}, HI = 0x{X:0>16}", .{isPipe1, tagRs, tagRt, regFile.lo.get(u64), regFile.hi.get(u64)});
        } else {
            info("   [EE Core   ] MULT{s} ${s}, ${s}, ${s}; ${s}/LO = 0x{X:0>16}, HI = 0x{X:0>16}", .{isPipe1, tagRd, tagRs, tagRt, tagRd, regFile.lo.get(u64), regFile.hi.get(u64)});
        }
    }
}

/// OR
fn iOr(instr: u32) void {
    const rd = getRs(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(u64, rs) | regFile.get(u64, rt);

    regFile.set(u64, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] OR ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, res});
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

/// Store Byte
fn iSb(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const data = @truncate(u8, regFile.get(u32, rt));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SB ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>2}", .{tagRt, imm16s, tagRs, addr, data});
    }

    write(u8, addr, data);
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

/// Store Halfword
fn iSh(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const data = @truncate(u16, regFile.get(u32, rt));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SH ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>4}", .{tagRt, imm16s, tagRs, addr, data});
    }

    if ((addr & 1) != 0) {
        err("  [EE Core   ] Unhandled AdES @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    write(u16, addr, data);
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

/// Set Less Than
fn iSlt(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, @as(u64, @bitCast(u1, @bitCast(i64, regFile.get(u64, rs)) < @intCast(i64, regFile.get(u64, rt)))));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SLT ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(u64, rd)});
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

/// Set Less Than Immediate Unsigned
fn iSltiu(instr: u32) void {
    const imm16s = exts(u64, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rt, @as(u64, @bitCast(u1, regFile.get(u64, rs) < imm16s)));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SLTIU ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(u64, rt)});
    }
}

/// Set Less Than Unsigned
fn iSltu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, @as(u64, @bitCast(u1, regFile.get(u64, rs) < regFile.get(u64, rt))));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SLTU ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(u64, rd)});
    }
}

/// Shift Right Arithmetic
fn iSra(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, @truncate(u32, @bitCast(u64, @bitCast(i64, regFile.get(u64, rt)) >> sa)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SRA ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Shift Right Logical
fn iSrl(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, @truncate(u32, regFile.get(u64, rt) >> sa));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SRL ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// SUBtract Unsigned
fn iSubu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, @truncate(u32, regFile.get(u64, rs) -% regFile.get(u64, rt)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SUBU ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(u64, rd)});
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

/// Store Word Coprocessor
fn iSwc(instr: u32, comptime n: u2) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    var data: u32 = undefined;

    if (!cop0.isCopUsable(n)) {
        err("  [EE Core   ] Coprocessor {} is unusable!", .{n});

        assert(false);
    }

    switch (n) {
        1 => data = cop1.getRaw(rt),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        info("   [EE Core   ] SWC{} ${}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>8}", .{n, rt, imm16s, tagRs, addr, data});
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

/// XOR Immediate
fn iXori(instr: u32) void {
    const imm16 = getImm16(instr);

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rt, regFile.get(u64, rs) ^ @as(u64, imm16));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] XORI ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16, tagRt, regFile.get(u64, rt)});
    }
}

/// Steps the EE Core interpreter
pub fn step() void {
    regFile.cpc = regFile.pc;

    inDelaySlot[0] = inDelaySlot[1];
    inDelaySlot[1] = false;

    decodeInstr(fetchInstr());

    cop0.incrementCount();
}
