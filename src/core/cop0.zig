//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cop0.zig - EmotionEngine Core COP0
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const exts = @import("../common/extend.zig").exts;

/// COP0 register aliases
pub const Cop0Reg = enum(u32) {
    Index       =  0,
    Random      =  1,
    EntryLo0    =  2,
    EntryLo1    =  3,
    Context     =  4,
    PageMask    =  5,
    Wired       =  6,
    R7          =  7,
    BadVAddr    =  8,
    Count       =  9,
    EntryHi     = 10,
    Compare     = 11,
    Status      = 12,
    Cause       = 13,
    EPC         = 14,
    PRId        = 15,
    Config      = 16,
    LLAddr      = 17,
    WatchLo     = 18,
    WatchHi     = 19,
    XContext    = 20,
    R21         = 21,
    R22         = 22,
    R23         = 23,
    R24         = 24,
    R25         = 25,
    ParityError = 26,
    CacheError  = 27,
    TagLo       = 28,
    TagHi       = 29,
    ErrorEPC    = 30,
    R31         = 31,
};

/// COP0 Config register
const Config = struct {
     k0: u3   = undefined, // KSEG0 cache mode
    bpe: bool = false,     // Branch Prediction Enable
    nbe: bool = false,     // Non-Blocking load Enable
    dce: bool = false,     // Data Cache Enable
    ice: bool = false,     // Instruction Cache Enable
    die: bool = false,     // Double Issue Enable

    /// Returns Config
    pub fn get(self: Config) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.k0);
        data |= 1 << 6; // Data Cache size
        data |= 2 << 9; // Instruction Cache size
        data |= @as(u32, @bitCast(u1, self.bpe)) << 12;
        data |= @as(u32, @bitCast(u1, self.nbe)) << 13;
        data |= @as(u32, @bitCast(u1, self.dce)) << 16;
        data |= @as(u32, @bitCast(u1, self.ice)) << 17;
        data |= @as(u32, @bitCast(u1, self.die)) << 18;

        return data;
    }

    /// Sets Config
    pub fn set(self: *Config, data: u32) void {
        self.k0  = @truncate(u3, data);
        self.bpe = (data & (1 << 12)) != 0;
        self.nbe = (data & (1 << 13)) != 0;
        self.dce = (data & (1 << 16)) != 0;
        self.ice = (data & (1 << 17)) != 0;
        self.die = (data & (1 << 18)) != 0;
    }
};

/// COP0 EntryHi register
const EntryHi = struct {
    asid: u8  = undefined, // Address Space IDentifier
    vpn2: u19 = undefined, // Virtual Page Number / 2

    /// Returns EntryHi
    pub fn get(self: EntryHi) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.asid);
        data |= @as(u32, self.vpn2) << 13;

        return data;
    }

    /// Set EntryHi
    pub fn set(self: *EntryHi, data: u32) void {
        self.asid = @truncate(u8, data);
        self.vpn2 = @truncate(u19, data >> 13);
    }
};

/// COP0 EntryLo registers
const EntryLo = struct {
    /// Is this EntryLo0?
    is0: bool,

      g: bool = undefined, // Global
      v: bool = undefined, // Valid
      d: bool = undefined, // Dirty
      c: u3   = undefined, // Cache mode
    pfn: u20  = undefined, // Page Frame Number
      s: bool = undefined, // Scratchpad (EntryLo0 only)
    
    /// Returns EntryLo
    pub fn get(self: EntryLo) u32 {
        var data: u32 = 0;

        data |= @as(u32, @bitCast(u1, self.g));
        data |= @as(u32, @bitCast(u1, self.v)) << 1;
        data |= @as(u32, @bitCast(u1, self.d)) << 2;
        data |= @as(u32, self.c  ) << 3;
        data |= @as(u32, self.pfn) << 6;

        if (self.is0) {
            data |= @as(u32, @bitCast(u1, self.s)) << 31;
        }

        return data;
    }

    /// Sets EntryLo
    pub fn set(self: *EntryLo, data: u32) void {
        self.g   = (data & 1) != 0;
        self.v   = (data & (1 << 1)) != 0;
        self.d   = (data & (1 << 2)) != 0;
        self.c   = @truncate(u3 , data >> 3);
        self.pfn = @truncate(u20, data >> 6);

        if (self.is0) {
            self.s = (data & (1 << 31)) != 0;
        }
    }
};

/// COP0 Index register
const Index = struct {
    index: u6   = undefined, // TLB index
        p: bool = undefined, // Software bit
    
    /// Returns Index
    pub fn get(self: Index) u32 {
        var data: u32 = 0;

        data |= @as(u32, self.index);
        data |= @as(u32, @bitCast(u1, self.p)) << 31;

        return data;
    }

    /// Sets Index
    pub fn set(self: *Index, data: u32) void {
        self.index = @truncate(u6, data);
        self.p     = (data & (1 << 31)) != 0;
    }
};

/// COP0 Status register
const Status = struct {
    ie : bool = undefined, // Interrupt Enable
    exl: bool = undefined, // EXception Level
    erl: bool = true,      // ERror Level
    ksu: u2   = 0,         // Kernel/Supervisor/User mode
    bem: bool = undefined, // Bus Error Mask
     im: u3   = undefined, // Interrupt Mask
    eie: bool = undefined, // Enable IE bit
    edi: bool = undefined, // Enable EI/DI
     ch: bool = undefined, // Cache Hit
    bev: bool = true,      // Boot Exception Vector
    dev: bool = undefined, // Debug Exception Vector
     cu: u4   = undefined, // Coprocessor Usable

    // Returns Status
    pub fn get(self: Status) u32 {
        var data: u32 = 0;

        data |= @as(u32, @bitCast(u1, self.ie ));
        data |= @as(u32, @bitCast(u1, self.exl)) << 1;
        data |= @as(u32, @bitCast(u1, self.erl)) << 2;
        data |= @as(u32, self.ksu) << 3;
        data |= @as(u32, self.im & 3) << 10;
        data |= @as(u32, @bitCast(u1, self.bem)) << 12;
        data |= @as(u32, self.im & 4) << 13;
        data |= @as(u32, @bitCast(u1, self.eie)) << 16;
        data |= @as(u32, @bitCast(u1, self.edi)) << 17;
        data |= @as(u32, @bitCast(u1, self.ch )) << 18;
        data |= @as(u32, @bitCast(u1, self.bev)) << 22;
        data |= @as(u32, @bitCast(u1, self.dev)) << 23;
        data |= @as(u32, self.cu) << 28;

        return data;
    }

    /// Sets Status
    pub fn set(self: *Status, data: u32) void {
        self.ie  = (data & 1) != 0;
        self.exl = (data & (1 << 1)) != 0;
        self.erl = (data & (1 << 2)) != 0;
        self.ksu = @truncate(u2, data >> 3);
        self.im  = @truncate(u3, (data >> 10) & 3);
        self.bem = (data & (1 << 12)) != 0;
        self.im |= @truncate(u3, (data >> 13) & 4);
        self.eie = (data & (1 << 16)) != 0;
        self.edi = (data & (1 << 17)) != 0;
        self.ch  = (data & (1 << 18)) != 0;
        self.bev = (data & (1 << 22)) != 0;
        self.dev = (data & (1 << 23)) != 0;
        self.cu  = @truncate(u4, data >> 28);
    }
};

/// TLB entry
const TlbEntry = struct {
      v1: bool = undefined, // Valid1
      d1: bool = undefined, // Dirty1
      c1: u3   = undefined, // Cache mode1
    pfn1: u20  = undefined, // Page Frame Number1
      v0: bool = undefined, // Valid0
      d0: bool = undefined, // Dirty0
      c0: u3   = undefined, // Cache mode0
    pfn0: u20  = undefined, // Page Frame Number0
       s: bool = undefined, // Scratchpad
    asid: u8   = undefined, // Address Space IDentifier
       g: bool = undefined, // Global
    vpn2: u19  = undefined, // Virtual Page Number / 2
    mask: u12  = undefined, // page MASK

    /// Returns TLB entry
    pub fn get(self: TlbEntry) u128 {
        var data: u128 = 0;

        data |= @as(u128, @bitCast(u1, self.v1)) << 1;
        data |= @as(u128, @bitCast(u1, self.d1)) << 2;
        data |= @as(u128, self.c1  ) << 3;
        data |= @as(u128, self.pfn1) << 6;

        data |= @as(u128, @bitCast(u1, self.v0)) << 33;
        data |= @as(u128, @bitCast(u1, self.d0)) << 34;
        data |= @as(u128, self.c0  ) << 35;
        data |= @as(u128, self.pfn0) << 38;
        data |= @as(u128, @bitCast(u1, self.s)) << 63;

        data |= @as(u128, self.asid) << 64;
        data |= @as(u128, @bitCast(u1, self.g)) << 76;
        data |= @as(u128, self.vpn2) << 77;

        data |= @as(u128, self.mask) << 109;

        return data;
    }
};

/// COP0 register file (private)
var  compare: u32 = undefined;
var    count: u32 = undefined;
var pagemask: u12 = undefined;

var   config: Config  =  Config{};
var  entryhi: EntryHi = EntryHi{};
var entrylo0: EntryLo = EntryLo{.is0 = true};
var entrylo1: EntryLo = EntryLo{.is0 = false};
var    index: Index   =   Index{};
var   status: Status  =  Status{};

/// TLB entries
var tlbEntry: [32]TlbEntry = undefined;

/// Initializes the COP0 module
pub fn init() void {}

/// Returns a COP0 register
pub fn get(comptime T: type, idx: u5) T {
    assert(T == u32 or T == u64);

    var data: T = undefined;

    switch (idx) {
        @enumToInt(Cop0Reg.PRId) => data = @as(T, 0x59),
        else => {
            err("  [COP0 (EE) ] Unhandled register read ({s}) @ {s}.", .{@typeName(T), @tagName(@intToEnum(Cop0Reg, idx))});

            assert(false);
        }
    }

    return data;
}

/// Sets a COP0 register
pub fn set(comptime T: type, idx: u5, data: T) void {
    assert(T == u32 or T == u64);

    switch (idx) {
        @enumToInt(Cop0Reg.Index   ) => index.set(data),
        @enumToInt(Cop0Reg.EntryLo0) => entrylo0.set(data),
        @enumToInt(Cop0Reg.EntryLo1) => entrylo1.set(data),
        @enumToInt(Cop0Reg.PageMask) => pagemask = @truncate(u12, data >> 13),
        @enumToInt(Cop0Reg.Count   ) => count = data,
        @enumToInt(Cop0Reg.EntryHi ) => entryhi.set(data),
        @enumToInt(Cop0Reg.Compare ) => compare = data,
        @enumToInt(Cop0Reg.Status  ) => status.set(data),
        @enumToInt(Cop0Reg.Config  ) => config.set(data),
        else => {
            err("  [COP0 (EE) ] Unhandled register write ({s}) @ {s} = 0x{X:0>8}.", .{@typeName(T), @tagName(@intToEnum(Cop0Reg, idx)), data});

            assert(false);
        }
    }
}

/// Writes an indexed TLB entry
pub fn setEntryIndexed() void {
    const idx = index.index;

    tlbEntry[idx].v1   = entrylo1.v;
    tlbEntry[idx].d1   = entrylo1.d;
    tlbEntry[idx].c1   = entrylo1.c;
    tlbEntry[idx].pfn1 = entrylo1.pfn;

    tlbEntry[idx].v0   = entrylo0.v;
    tlbEntry[idx].d0   = entrylo0.d;
    tlbEntry[idx].c0   = entrylo0.c;
    tlbEntry[idx].pfn0 = entrylo0.pfn;
    tlbEntry[idx].s    = entrylo0.s;

    tlbEntry[idx].asid = entryhi.asid;
    tlbEntry[idx].g    = entrylo0.g and entrylo1.g;
    tlbEntry[idx].vpn2 = entryhi.vpn2;

    tlbEntry[idx].mask = pagemask;

    info("   [COP0 (EE) ] Indexed write @ TLB entry {} = 0x{X:0>32}.", .{idx, tlbEntry[idx].get()});
}
