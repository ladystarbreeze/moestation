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
const ExCode  = cop0.ExCode;

const cop1 = @import("cop1.zig");

const vu0 = @import("vu0.zig");

const exts = @import("../common/extend.zig").exts;

/// Enable/disable disassembler
var doDisasm = false;

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
    Cop1    = 0x11,
    Cop2    = 0x12,
    Beql    = 0x14,
    Bnel    = 0x15,
    Blezl   = 0x16,
    Daddiu  = 0x19,
    Ldl     = 0x1A,
    Ldr     = 0x1B,
    Mmi     = 0x1C,
    Lq      = 0x1E,
    Sq      = 0x1F,
    Lb      = 0x20,
    Lh      = 0x21,
    Lw      = 0x23,
    Lbu     = 0x24,
    Lhu     = 0x25,
    Lwu     = 0x27,
    Sb      = 0x28,
    Sh      = 0x29,
    Sw      = 0x2B,
    Sdl     = 0x2C,
    Sdr     = 0x2D,
    Cache   = 0x2F,
    Lwc1    = 0x31,
    Ld      = 0x37,
    Swc1    = 0x39,
    Sd      = 0x3F,
};

/// SPECIAL instructions
const Special = enum(u6) {
    Sll     = 0x00,
    Srl     = 0x02,
    Sra     = 0x03,
    Sllv    = 0x04,
    Srlv    = 0x06,
    Srav    = 0x07,
    Jr      = 0x08,
    Jalr    = 0x09,
    Movz    = 0x0A,
    Movn    = 0x0B,
    Syscall = 0x0C,
    Sync    = 0x0F,
    Mfhi    = 0x10,
    Mthi    = 0x11,
    Mflo    = 0x12,
    Mtlo    = 0x13,
    Dsllv   = 0x14,
    Dsrav   = 0x17,
    Mult    = 0x18,
    Div     = 0x1A,
    Divu    = 0x1B,
    Addu    = 0x21,
    Subu    = 0x23,
    And     = 0x24,
    Or      = 0x25,
    Nor     = 0x27,
    Mfsa    = 0x28,
    Mtsa    = 0x29,
    Slt     = 0x2A,
    Sltu    = 0x2B,
    Daddu   = 0x2D,
    Dsubu   = 0x2F,
    Dsll    = 0x38,
    Dsrl    = 0x3A,
    Dsll32  = 0x3C,
    Dsrl32  = 0x3E,
    Dsra32  = 0x3F,
};

/// REGIMM instructions
const Regimm = enum(u5) {
    Bltz  = 0x00,
    Bgez  = 0x01,
    Bltzl = 0x02,
    Bgezl = 0x03,
};

/// COP instructions
const CopOpcode = enum(u5) {
    Mf = 0x00,
    Cf = 0x02,
    Mt = 0x04,
    Ct = 0x06,
    Co = 0x10,
};

/// COP1 instructions
const Cop1Opcode = enum(u5) {
    S = 0x10,
};

/// COP1 Single instructions
const Cop1Single = enum(u6) {
    Adda = 0x18,
    Madd = 0x1C,
};

/// COP2 instructions
const Cop2Opcode = enum(u5) {
    Qmfc2 = 0x01,
    Qmtc2 = 0x05,
};

/// COP Control instructions
const ControlOpcode = enum(u6) {
    Tlbwi = 0x02,
    Eret  = 0x18,
    Ei    = 0x38,
    Di    = 0x39,
};

/// MMI instructions
const MmiOpcode = enum(u6) {
    Plzcw = 0x04,
    Mmi2  = 0x09,
    Mfhi1 = 0x10,
    Mthi1 = 0x11,
    Mflo1 = 0x12,
    Mtlo1 = 0x13,
    Mult1 = 0x18,
    Divu1 = 0x1B,
    Mmi1  = 0x28,
    Mmi3  = 0x29,
};

/// MMI1 instructions
const Mmi1Opcode = enum(u5) {
    Padduw = 0x10,
};

/// MMI2 instructions
const Mmi2Opcode = enum(u5) {
    Pmfhi = 0x08,
    Pmflo = 0x09,
};

/// MMI3 instructions
const Mmi3Opcode = enum(u5) {
    Por = 0x12,
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

    sa: u8 = 0,

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

/// Interrupt pending flag
var intPending = false;

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
    
    const data = bus.read(T, pAddr);

    return data;
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
                @enumToInt(Special.Sll    ) => iSll(instr),
                @enumToInt(Special.Srl    ) => iSrl(instr),
                @enumToInt(Special.Sra    ) => iSra(instr),
                @enumToInt(Special.Sllv   ) => iSllv(instr),
                @enumToInt(Special.Srlv   ) => iSrlv(instr),
                @enumToInt(Special.Srav   ) => iSrav(instr),
                @enumToInt(Special.Jr     ) => iJr(instr),
                @enumToInt(Special.Jalr   ) => iJalr(instr),
                @enumToInt(Special.Movz   ) => iMovz(instr),
                @enumToInt(Special.Movn   ) => iMovn(instr),
                @enumToInt(Special.Syscall) => iSyscall(),
                @enumToInt(Special.Sync   ) => iSync(instr),
                @enumToInt(Special.Mfhi   ) => iMfhi(instr, false),
                @enumToInt(Special.Mthi   ) => iMthi(instr, false),
                @enumToInt(Special.Mflo   ) => iMflo(instr, false),
                @enumToInt(Special.Mtlo   ) => iMtlo(instr, false),
                @enumToInt(Special.Dsllv  ) => iDsllv(instr),
                @enumToInt(Special.Dsrav  ) => iDsrav(instr),
                @enumToInt(Special.Mult   ) => iMult(instr, 0),
                @enumToInt(Special.Div    ) => iDiv(instr),
                @enumToInt(Special.Divu   ) => iDivu(instr, 0),
                @enumToInt(Special.Addu   ) => iAddu(instr),
                @enumToInt(Special.Subu   ) => iSubu(instr),
                @enumToInt(Special.And    ) => iAnd(instr),
                @enumToInt(Special.Or     ) => iOr(instr),
                @enumToInt(Special.Nor    ) => iNor(instr),
                @enumToInt(Special.Mfsa   ) => iMfsa(instr),
                @enumToInt(Special.Mtsa   ) => iMtsa(instr),
                @enumToInt(Special.Slt    ) => iSlt(instr),
                @enumToInt(Special.Sltu   ) => iSltu(instr),
                @enumToInt(Special.Daddu  ) => iDaddu(instr),
                @enumToInt(Special.Dsubu  ) => iDsubu(instr),
                @enumToInt(Special.Dsll   ) => iDsll(instr),
                @enumToInt(Special.Dsrl   ) => iDsrl(instr),
                @enumToInt(Special.Dsll32 ) => iDsll32(instr),
                @enumToInt(Special.Dsrl32 ) => iDsrl32(instr),
                @enumToInt(Special.Dsra32 ) => iDsra32(instr),
                else => {
                    err("  [EE Core   ] Unhandled SPECIAL instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Regimm) => {
            const rt = getRt(instr);

            switch (rt) {
                @enumToInt(Regimm.Bltz ) => iBltz(instr),
                @enumToInt(Regimm.Bgez ) => iBgez(instr),
                @enumToInt(Regimm.Bltzl) => iBltzl(instr),
                @enumToInt(Regimm.Bgezl) => iBgezl(instr),
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
                        @enumToInt(ControlOpcode.Eret ) => iEret(),
                        @enumToInt(ControlOpcode.Ei   ) => iEi(),
                        @enumToInt(ControlOpcode.Di   ) => iDi(),
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
        @enumToInt(Opcode.Cop1 ) => {
            const rs = getRs(instr);

            switch (rs) {
                @enumToInt(CopOpcode.Cf) => iCfc(instr, 1),
                @enumToInt(CopOpcode.Mt) => iMtc(instr, 1),
                @enumToInt(CopOpcode.Ct) => iCtc(instr, 1),
                @enumToInt(Cop1Opcode.S) => {
                    const funct = getFunct(instr);

                    switch (funct) {
                        @enumToInt(Cop1Single.Adda) => cop1.iAdda(instr),
                        @enumToInt(Cop1Single.Madd) => cop1.iMadd(instr),
                        else => {
                            err("  [EE Core   ] Unhandled FPU Single instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                            assert(false);
                        }
                    }
                },
                else => {
                    err("  [EE Core   ] Unhandled FPU instruction 0x{X} (0x{X:0>8}).", .{rs, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Cop2 ) => {
            const rs = getRs(instr);

            if ((rs & (1 << 4)) != 0) {
                const funct = getFunct(instr);

                if ((funct >> 2) == 0xF) {
                    const sa = getSa(instr);

                    switch (sa) {
                        0x0D => {
                            switch (funct) {
                                0x3D => vu0.iSqi(instr),
                                else => {
                                    err("  [EE Core   ] Unhandled 11-bit VU0 macro instruction (0x0D) 0x{X} (0x{X:0>8}).", .{funct, instr});

                                    assert(false);
                                }
                            }
                        },
                        0x0F => {
                            switch (funct) {
                                0x3F => vu0.iIswr(instr),
                                else => {
                                    err("  [EE Core   ] Unhandled 11-bit VU0 macro instruction (0x0F) 0x{X} (0x{X:0>8}).", .{funct, instr});

                                    assert(false);
                                }
                            }
                        },
                        else => {
                            err("  [EE Core   ] Unhandled 11-bit VU0 macro instruction 0x{X} (0x{X:0>8}).", .{sa, instr});

                            assert(false);
                        }
                    }
                } else {
                    switch (funct) {
                        0x2C => vu0.iSub(instr),
                        0x30 => vu0.iIadd(instr),
                        else => {
                            err("  [EE Core   ] Unhandled VU0 macro instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                            assert(false);
                        }
                    }
                }
            } else {
                switch (rs & 0xF) {
                    @enumToInt(Cop2Opcode.Qmfc2) => iQmfc2(instr),
                    @enumToInt(CopOpcode.Cf    ) => iCfc(instr, 2),
                    @enumToInt(Cop2Opcode.Qmtc2) => iQmtc2(instr),
                    @enumToInt(CopOpcode.Ct    ) => iCtc(instr, 2),
                    else => {
                        err("  [EE Core   ] Unhandled COP2 instruction 0x{X} (0x{X:0>8}).", .{rs, instr});

                        assert(false);
                    }
                }
            }
        },
        @enumToInt(Opcode.Beql  ) => iBeql(instr),
        @enumToInt(Opcode.Bnel  ) => iBnel(instr),
        @enumToInt(Opcode.Blezl ) => iBlezl(instr),
        @enumToInt(Opcode.Daddiu) => iDaddiu(instr),
        @enumToInt(Opcode.Ldl   ) => iLdl(instr),
        @enumToInt(Opcode.Ldr   ) => iLdr(instr),
        @enumToInt(Opcode.Mmi   ) => {
            const funct = getFunct(instr);

            switch (funct) {
                @enumToInt(MmiOpcode.Plzcw) => iPlzcw(instr),
                @enumToInt(MmiOpcode.Mmi2 ) => {
                    const sa = getSa(instr);

                    switch (sa) {
                        @enumToInt(Mmi2Opcode.Pmfhi) => iPmfhi(instr),
                        @enumToInt(Mmi2Opcode.Pmflo) => iPmflo(instr),
                        else => {
                            err("  [EE Core   ] Unhandled MMI2 instruction 0x{X} (0x{X:0>8}).", .{sa, instr});

                            assert(false);
                        }
                    }
                },
                @enumToInt(MmiOpcode.Mfhi1) => iMfhi(instr, true),
                @enumToInt(MmiOpcode.Mthi1) => iMthi(instr, true),
                @enumToInt(MmiOpcode.Mflo1) => iMflo(instr, true),
                @enumToInt(MmiOpcode.Mtlo1) => iMtlo(instr, true),
                @enumToInt(MmiOpcode.Mult1) => iMult(instr, 1),
                @enumToInt(MmiOpcode.Divu1) => iDivu(instr, 1),
                @enumToInt(MmiOpcode.Mmi1 ) => {
                    const sa = getSa(instr);

                    switch (sa) {
                        @enumToInt(Mmi1Opcode.Padduw) => iPadduw(instr),
                        else => {
                            err("  [EE Core   ] Unhandled MMI1 instruction 0x{X} (0x{X:0>8}).", .{sa, instr});

                            assert(false);
                        }
                    }
                },
                @enumToInt(MmiOpcode.Mmi3) => {
                    const sa = getSa(instr);

                    switch (sa) {
                        @enumToInt(Mmi3Opcode.Por) => iPor(instr),
                        else => {
                            err("  [EE Core   ] Unhandled MMI3 instruction 0x{X} (0x{X:0>8}).", .{sa, instr});

                            assert(false);
                        }
                    }
                },
                else => {
                    err("  [EE Core   ] Unhandled MMI instruction 0x{X} (0x{X:0>8}).", .{funct, instr});

                    assert(false);
                }
            }
        },
        @enumToInt(Opcode.Lq   ) => iLq(instr),
        @enumToInt(Opcode.Sq   ) => iSq(instr),
        @enumToInt(Opcode.Lb   ) => iLb(instr),
        @enumToInt(Opcode.Lh   ) => iLh(instr),
        @enumToInt(Opcode.Lw   ) => iLw(instr),
        @enumToInt(Opcode.Lbu  ) => iLbu(instr),
        @enumToInt(Opcode.Lhu  ) => iLhu(instr),
        @enumToInt(Opcode.Lwu  ) => iLwu(instr),
        @enumToInt(Opcode.Sb   ) => iSb(instr),
        @enumToInt(Opcode.Sh   ) => iSh(instr),
        @enumToInt(Opcode.Sw   ) => iSw(instr),
        @enumToInt(Opcode.Sdl  ) => iSdl(instr),
        @enumToInt(Opcode.Sdr  ) => iSdr(instr),
        @enumToInt(Opcode.Cache) => iCache(instr),
        @enumToInt(Opcode.Lwc1 ) => iLwc(instr, 1),
        @enumToInt(Opcode.Ld   ) => iLd(instr),
        @enumToInt(Opcode.Swc1 ) => iSwc(instr, 1),
        @enumToInt(Opcode.Sd   ) => iSd(instr),
        else => {
            err("  [EE Core   ] Unhandled instruction 0x{X} (0x{X:0>8}).", .{opcode, instr});

            assert(false);
        }
    }
}

/// Sets irqPending if interrupt is pending
pub fn checkIntPending() void {
    const intEnabled = cop0.isIe() and cop0.isEie() and !cop0.isErl() and !cop0.isExl();

    // info("   [EE Core   ] IE = {}, EIE = {}, ERL = {}, EXL = {}", .{cop0.isIe(), cop0.isEie(), cop0.isErl(), cop0.isExl()});
    // info("   [EE Core   ] IM = 0b{b:0>3}, IP = 0b{b:0>3}", .{cop0.getIm(), cop0.getIp()});

    intPending = intEnabled and (cop0.getIm() & cop0.getIp()) != 0;
}

/// Raises a generic Level 1 CPU exception
fn raiseExceptionL1(excode: ExCode) void {
    info("   [EE Core   ] {s} exception @ 0x{X:0>8}.", .{@tagName(excode), regFile.cpc});

    cop0.setExCode(excode);

    var exVector: u32 = if (cop0.isBev()) 0xBFC0_0200 else 0x8000_0000;

    if (excode == ExCode.Interrupt) {
        exVector += 0x200;
    } else {
        exVector += 0x180;
    }

    if (!cop0.isExl()) {
        cop0.setBranchDelay(inDelaySlot[0]);

        if (inDelaySlot[0]) {
            cop0.setErrorPc(regFile.cpc - 4);
        } else {
            cop0.setErrorPc(regFile.cpc);
        }
    }

    inDelaySlot[0] = false;
    inDelaySlot[1] = false;

    cop0.setExl(true);

    regFile.setPc(exVector);
}

/// Branch helper
fn doBranch(target: u32, isCond: bool, rd: u5, comptime isLikely: bool) void {
    regFile.set(u64, rd, @as(u64, regFile.npc));

    inDelaySlot[1] = true;

    if (isCond) {
        regFile.npc = target;
    } else if (isLikely) {
        regFile.setPc(regFile.npc);

        inDelaySlot[1] = false;
    }
}

/// ADD Immediate Unsigned
fn iAddiu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rt, regFile.get(u32, rs) +% imm16s);

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

    regFile.set(u32, rd, regFile.get(u32, rs) +% regFile.get(u32, rt));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] ADDU ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, regFile.get(u64, rd)});
    }
}

/// AND
fn iAnd(instr: u32) void {
    const rd = getRd(instr);
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

/// Branch on Greater than or Equal Zero Likely
fn iBgezl(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) >= 0, @enumToInt(CpuReg.R0), true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BGEZL ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
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

/// Branch on Less than or Equal Zero Likely
fn iBlezl(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) <= 0, @enumToInt(CpuReg.R0), true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BLEZL ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
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

/// Branch on Less Than Zero Likely
fn iBltzl(instr: u32) void {
    const offset = exts(u32, u16, getImm16(instr)) << 2;

    const rs = getRs(instr);

    const target = regFile.pc +% offset;

    doBranch(target, @bitCast(i64, regFile.get(u64, rs)) < 0, @enumToInt(CpuReg.R0), true);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        
        info("   [EE Core   ] BLTZL ${s}, 0x{X:0>8}; ${s} = 0x{X:0>16}", .{tagRs, target, tagRs, regFile.get(u64, rs)});
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

/// CACHE
fn iCache(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        info("   [EE Core   ] CACHE 0x{X:0>2}, 0x{X}(${s}); ADDR = 0x{X:0>8}", .{rt, imm16s, tagRs, addr});
    }
}

/// move From Control
fn iCfc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    var data: u32 = undefined;

    switch (n) {
        1 => data = cop1.getControl(rd),
        2 => data = vu0.getControl(u32, rd),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    regFile.set(u32, rt, data);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [EE Core   ] CFC{} ${s}, ${}; ${s} = 0x{X:0>16}", .{n, tagRt, rd, tagRt, regFile.get(u64, rt)});
    }
}

/// move To Control
fn iCtc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    const data = regFile.get(u32, rt);

    switch (n) {
        1 => cop1.setControl(rd, data),
        2 => vu0.setControl(u32, rd, data),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [EE Core   ] CTC{} ${s}, ${}; ${} = 0x{X:0>8}", .{n, tagRt, rd, rd, data});
    }
}

/// Doubleword ADD Immediate Unsigned
fn iDaddiu(instr: u32) void {
    const imm16s = exts(u64, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rt, regFile.get(u64, rs) +% imm16s);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DADDIU ${s}, ${s}, 0x{X}; ${s} = 0x{X:0>16}", .{tagRt, tagRs, imm16s, tagRt, regFile.get(u64, rt)});
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

/// Disable Interrupts
fn iDi() void {
    if (doDisasm) {
        info("   [EE Core   ] DI", .{});
    }

    if (cop0.isEdiEnabled()) {
        cop0.setEie(false);
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

/// Doubleword Shift Left Logical
fn iDsll(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, regFile.get(u64, rt) << @as(u6, sa));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSLL ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
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

/// Doubleword Shift Left Logical Variable
fn iDsllv(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, regFile.get(u64, rt) << @truncate(u6, regFile.get(u64, rs)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSLLV ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, tagRs, tagRd, regFile.get(u64, rd)});
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

/// Doubleword Shift Right Logical
fn iDsrl(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, regFile.get(u64, rt) >> @as(u6, sa));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSRL ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Doubleword Shift Right Logical + 32
fn iDsrl32(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u64, rd, regFile.get(u64, rt) >> (@as(u6, sa) + 32));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSRL32 ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Doubleword SUBtract Unsigned
fn iDsubu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(u64, rs) -% regFile.get(u64, rt);

    regFile.set(u64, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] DSUBU ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// Enable Interrupts
fn iEi() void {
    if (doDisasm) {
        info("   [EE Core   ] EI", .{});
    }

    if (cop0.isEdiEnabled()) {
        cop0.setEie(true);
    }
}

/// Exception RETurn
fn iEret() void {
    if (doDisasm) {
        info ("   [EE Core   ] ERET", .{});
    }

    if (cop0.isErl()) {
        regFile.setPc(cop0.getErrorEpc());

        cop0.setErl(false);
    } else {
        regFile.setPc(cop0.getErrorPc());

        cop0.setExl(false);
    }

    if (regFile.pc == 0x82000) {
        bus.fastBoot();
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

/// LDL - Load Doubleword Left
fn iLdl(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const addrMask = addr & ~@as(u32, 7);

    const shift = @truncate(u6, 56 - 8 * (addr & 7));
    const mask = ~((~@as(u64, 0)) << shift);

    const data = (regFile.get(u64, rt) & mask) | (read(u64, addrMask) << shift);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LDL ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
}

/// LDR - Load Doubleword Right
fn iLdr(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const addrMask = addr & ~@as(u32, 7);

    const shift = @truncate(u6, 8 * (addr & 7));
    const mask = ~((~@as(u64, 0)) >> shift);

    const data = (regFile.get(u64, rt) & mask) | (read(u64, addrMask) >> shift);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LDR ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
}

/// Load Halfword
fn iLh(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if ((addr & 1) != 0) {
        err("  [EE Core   ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = exts(u64, u16, read(u16, addr));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LH ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
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

/// Load Quadword
fn iLq(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = (regFile.get(u32, rs) +% imm16s) & ~@as(u32, 15);

    const data = read(u128, addr);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LD ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>32}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u128, rt, data);
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

/// Load Word Coprocessor
fn iLwc(instr: u32, comptime n: u2) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if (!cop0.isCopUsable(n)) {
        err("  [EE Core   ] Coprocessor {} is unusable!", .{n});

        assert(false);
    }

    if ((addr & 3) != 0) {
        err("  [EE Core   ] Unhandled AdES @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = read(u32, addr);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        info("   [EE Core   ] LWC{} ${}, 0x{X}(${s}); ${}, [0x{X:0>8}] = 0x{X:0>8}", .{n, rt, imm16s, tagRs, rt, addr, data});
    }

    switch (n) {
        1 => cop1.setRaw(rt, data),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }
}

/// Load Word Unsigned
fn iLwu(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;

    if ((addr & 3) != 0) {
        err("  [EE Core   ] Unhandled AdEL @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    const data = @as(u64, read(u32, addr));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] LWU ${s}, 0x{X}(${s}); ${s} = [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, tagRt, addr, data});
    }

    regFile.set(u64, rt, data);
}

/// Move From Coprocessor
fn iMfc(instr: u32, comptime n: u2) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    if (!cop0.isCopUsable(n)) {
        err("  [EE Core   ] Coprocessor {} is unusable!", .{n});

        assert(false);
    }

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
    
        info("   [EE Core   ] MFC{} ${s}, ${}; ${s} = 0x{X:0>8}", .{n, tagRt, rd, tagRt, regFile.get(u32, rt)});
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

/// Move From Shift Amount
fn iMfsa(instr: u32) void {
    const rd = getRd(instr);

    regFile.set(u64, rd, @as(u64, regFile.sa));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));

        info("   [EE Core   ] MFSA ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRd, regFile.sa});
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

    if (!cop0.isCopUsable(n)) {
        err("  [EE Core   ] Coprocessor {} is unusable!", .{n});

        assert(false);
    }

    const data = regFile.get(u32, rt);

    switch (n) {
        0 => cop0.set(u32, rd, data),
        1 => cop1.setRaw(rd, data),
        else => {
            err("  [EE Core   ] Unhandled coprocessor {}.", .{n});

            assert(false);
        }
    }

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [EE Core   ] MTC{} ${s}, ${}; ${} = 0x{X:0>8}", .{n, tagRt, rd, rd, regFile.get(u32, rt)});
    }
}

/// Move To HI
fn iMthi(instr: u32, isHi: bool) void {
    const rs = getRd(instr);

    const data = regFile.get(u64, rs);
    
    if (isHi) {
        regFile.hi.setHi(u64, data);
    } else {
        regFile.hi.set(u64, data);
    }

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        const is1 = if (isHi) "1" else "";

        info("   [EE Core   ] MTHI{s} ${s}; HI{s} = 0x{X:0>16}", .{is1, tagRs, is1, data});
    }
}

/// Move To LO
fn iMtlo(instr: u32, isHi: bool) void {
    const rs = getRd(instr);

    const data = regFile.get(u64, rs);
    
    if (isHi) {
        regFile.lo.setHi(u64, data);
    } else {
        regFile.lo.set(u64, data);
    }

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        const is1 = if (isHi) "1" else "";

        info("   [EE Core   ] MTLO{s} ${s}; LO{s} = 0x{X:0>16}", .{is1, tagRs, is1, data});
    }
}

/// Move To Shift Amount
fn iMtsa(instr: u32) void {
    const rs = getRs(instr);

    regFile.sa = @truncate(u8, regFile.get(u32, rs));

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        info("   [EE Core   ] MTSA ${s}; SA = 0x{X:0>2}", .{tagRs, regFile.sa});
    }
}

/// MULTiply
fn iMult(instr: u32, comptime pipeline: u1) void {
    const rd = getRd(instr);
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

/// NOR
fn iNor(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = ~(regFile.get(u64, rs) | regFile.get(u64, rt));

    regFile.set(u64, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] NOR ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// OR
fn iOr(instr: u32) void {
    const rd = getRd(instr);
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

/// Parallel ADD Unsigned saturation Word
fn iPadduw(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const a = regFile.get(u128, rs);
    const b = regFile.get(u128, rt);

    var res: u128 = 0;

    var i: u7 = 0;
    while (i < 4) : (i += 1) {
        res |= @as(u128, @truncate(u32, a >> (32 * i)) +| @truncate(u32, b >> (32 * i))) << (32 * i);
    }

    regFile.set(u128, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] PADDUW ${s}, ${s}, ${s}; ${s} = 0x{X:0>32}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// Parallel Leading Zero or one Count Word
fn iPlzcw(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);

    const lo = @truncate(u32, regFile.get(u64, rs));
    const hi = @truncate(u32, regFile.get(u64, rs) >> 32);

    var res: u64 = undefined;

    if ((lo & (1 << 31)) != 0) {
        res = @as(u64, @clz(u32, ~lo) - 1);
    } else {
        res = @as(u64, @clz(u32, lo) - 1);
    }

    if ((hi & (1 << 31)) != 0) {
        res |= @as(u64, @clz(u32, ~hi) - 1) << 32;
    } else {
        res |= @as(u64, @clz(u32, hi) - 1) << 32;
    }

    regFile.set(u64, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));

        info("   [EE Core   ] PLZCW ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRs, tagRd, res});
    }
}

/// Parallel Move From HI
fn iPmfhi(instr: u32) void {
    const rd = getRd(instr);

    var data = regFile.hi.get(u128);

    regFile.set(u128, rd, data);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));

        info("   [EE Core   ] PMFHI ${s}; ${s} = 0x{X:0>32}", .{tagRd, tagRd, data});
    }
}

/// Parallel Move From LO
fn iPmflo(instr: u32) void {
    const rd = getRd(instr);

    var data = regFile.lo.get(u128);

    regFile.set(u128, rd, data);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));

        info("   [EE Core   ] PMFLO ${s}; ${s} = 0x{X:0>32}", .{tagRd, tagRd, data});
    }
}

/// Parallel OR
fn iPor(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res = regFile.get(u128, rs) | regFile.get(u128, rt);

    regFile.set(u128, rd, res);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] POR ${s}, ${s}, ${s}; ${s} = 0x{X:0>32}", .{tagRd, tagRs, tagRt, tagRd, res});
    }
}

/// Quadword Move From Coprocessor 2
fn iQmfc2(instr: u32) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    if (!cop0.isCopUsable(2)) {
        err("  [EE Core   ] Coprocessor 2 is unusable!", .{});

        assert(false);
    }

    var data: u128 = vu0.get(u128, rd);

    regFile.set(u128, rt, data);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [EE Core   ] QMFC2 ${s}, ${}; ${s} = 0x{X:0>32}", .{tagRt, rd, tagRt, regFile.get(u128, rt)});
    }
}

/// Quadword Move To Coprocessor 2
fn iQmtc2(instr: u32) void {
    const rd = getRd(instr);
    const rt = getRt(instr);

    if (!cop0.isCopUsable(2)) {
        err("  [EE Core   ] Coprocessor 2 is unusable!", .{});

        assert(false);
    }

    const data = regFile.get(u128, rt);

    vu0.set(u128, rd, data);

    if (doDisasm) {
        const tagRt = @tagName(@intToEnum(CpuReg, rt));
    
        info("   [EE Core   ] QMTC2 ${s}, ${}; ${} = 0x{X:0>32}", .{tagRt, rd, rd, data});
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

/// SDL - Store Doubleword Left
fn iSdl(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const addrMask = addr & ~@as(u32, 7);

    const shift = @truncate(u6, 56 - 8 * (addr & 7));
    const mask = ~((~@as(u64, 0)) >> shift);

    const data = (read(u64, addrMask) & mask) | (regFile.get(u64, rt) >> shift);

    write(u64, addrMask, data);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SDL ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, addr, data});
    }
}

/// SDR - Store Doubleword Right
fn iSdr(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = regFile.get(u32, rs) +% imm16s;
    const addrMask = addr & ~@as(u32, 7);

    const shift = @truncate(u6, 8 * (addr & 7));
    const mask = ~((~@as(u64, 0)) << shift);

    const data = (read(u64, addrMask) & mask) | (regFile.get(u64, rt) << shift);

    write(u64, addrMask, data);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SDR ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>16}", .{tagRt, imm16s, tagRs, addr, data});
    }
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

/// Shift Left Logical Variable
fn iSllv(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, regFile.get(u32, rt) << @truncate(u5, regFile.get(u64, rs)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SLLV ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, tagRs, tagRd, regFile.get(u64, rd)});
    }
}

/// Set Less Than
fn iSlt(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    const res: u64 = if (@bitCast(i64, regFile.get(u64, rs)) < @bitCast(i64, regFile.get(u64, rt))) 1 else 0;

    regFile.set(u64, rd, res);

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

/// Store Quadword
fn iSq(instr: u32) void {
    const imm16s = exts(u32, u16, getImm16(instr));

    const rs = getRs(instr);
    const rt = getRt(instr);

    const addr = (regFile.get(u32, rs) +% imm16s) & ~@as(u32, 15);
    const data = regFile.get(u128, rt);

    if (doDisasm) {
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SQ ${s}, 0x{X}(${s}); [0x{X:0>8}] = 0x{X:0>32}", .{tagRt, imm16s, tagRs, addr, data});
    }

    write(u128, addr, data);
}

/// Shift Right Arithmetic
fn iSra(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, @bitCast(u32, @bitCast(i32, regFile.get(u32, rt)) >> sa));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SRA ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Shift Right Arithmetic Variable
fn iSrav(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, @bitCast(u32, @bitCast(i32, regFile.get(u32, rt)) >> @truncate(u5, regFile.get(u64, rs))));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SRAV ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, tagRs, tagRd, regFile.get(u64, rd)});
    }
}

/// Shift Right Logical
fn iSrl(instr: u32) void {
    const sa = getSa(instr);

    const rd = getRd(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, regFile.get(u32, rt) >> sa);

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SRL ${s}, ${s}, {}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, sa, tagRd, regFile.get(u64, rd)});
    }
}

/// Shift Right Logical Variable
fn iSrlv(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, regFile.get(u32, rt) >> @truncate(u5, regFile.get(u64, rs)));

    if (doDisasm) {
        const tagRd = @tagName(@intToEnum(CpuReg, rd));
        const tagRs = @tagName(@intToEnum(CpuReg, rs));
        const tagRt = @tagName(@intToEnum(CpuReg, rt));

        info("   [EE Core   ] SRLV ${s}, ${s}, ${s}; ${s} = 0x{X:0>16}", .{tagRd, tagRt, tagRs, tagRd, regFile.get(u64, rd)});
    }
}

/// SUBtract Unsigned
fn iSubu(instr: u32) void {
    const rd = getRd(instr);
    const rs = getRs(instr);
    const rt = getRt(instr);

    regFile.set(u32, rd, regFile.get(u32, rs) -% regFile.get(u32, rt));

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

/// SYStem CALL
fn iSyscall() void {
    if (true) {
        info("   [EE Core   ] SYSCALL 0x{X}", .{regFile.get(u64, @enumToInt(CpuReg.V1))});
    }

    raiseExceptionL1(ExCode.Syscall);
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

    cop0.incrementCount();

    if (intPending) {
        intPending = false;

        return raiseExceptionL1(ExCode.Interrupt);
    }

    decodeInstr(fetchInstr());
}

pub fn dumpRegs() void {
    info("   [EE Core   ] PC = 0x{X:0>8}, $RA = 0x{X:0>8}", .{regFile.cpc, regFile.get(u32, @enumToInt(CpuReg.RA))});
}
