//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! gs.zig - Graphics Synthesizer
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const Allocator = std.mem.Allocator;

const LinearFifo = std.fifo.LinearFifo;
const LinearFifoBufferType = std.fifo.LinearFifoBufferType;

const scheduleFinish = @import("gif.zig").scheduleFinish;

const intc = @import("intc.zig");

const IntSource = intc.IntSource;
const IntSourceIop = intc.IntSourceIop;

const timer = @import("timer.zig");
const timerIop = @import("timer_iop.zig");

const setButtonState = @import("sio2.zig").setButtonState;

const main = @import("../main.zig");

const poll = main.poll;
const renderScreen  = main.renderScreen;
const getController = main.getController;

const max = @import("../common/min_max.zig").max;
const min = @import("../common/min_max.zig").min;

/// GS registers
pub const GsReg = enum(u8) {
    Prim       = 0x00,
    Rgbaq      = 0x01,
    St         = 0x02,
    Uv         = 0x03,
    Xyzf2      = 0x04,
    Xyz2       = 0x05,
    Tex01      = 0x06,
    Tex02      = 0x07,
    Clamp1     = 0x08,
    Clamp2     = 0x09,
    Fog        = 0x0A,
    Xyzf3      = 0x0C,
    Xyz3       = 0x0D,
    AddrData   = 0x0E,
    Tex11      = 0x14,
    Tex12      = 0x15,
    Tex21      = 0x16,
    Tex22      = 0x17,
    XyOffset1  = 0x18,
    XyOffset2  = 0x19,
    PrModeCont = 0x1A,
    PrMode     = 0x1B,
    TexClut    = 0x1C,
    ScanMsk    = 0x22,
    MipTbp11   = 0x34,
    MipTbp12   = 0x35,
    MipTbp21   = 0x36,
    MipTbp22   = 0x37,
    TexA       = 0x3B,
    FogCol     = 0x3D,
    TexFlush   = 0x3F,
    Scissor1   = 0x40,
    Scissor2   = 0x41,
    Alpha1     = 0x42,
    Alpha2     = 0x43,
    Dimx       = 0x44,
    Dthe       = 0x45,
    ColClamp   = 0x46,
    Test1      = 0x47,
    Test2      = 0x48,
    Pabe       = 0x49,
    Fba1       = 0x4A,
    Fba2       = 0x4B,
    Frame1     = 0x4C,
    Frame2     = 0x4D,
    Zbuf1      = 0x4E,
    Zbuf2      = 0x4F,
    BitBltBuf  = 0x50,
    TrxPos     = 0x51,
    TrxReg     = 0x52,
    TrxDir     = 0x53,
    Hwreg      = 0x54,
    Signal     = 0x60,
    Finish     = 0x61,
    Label      = 0x62,
};

/// GS privileged registers
const PrivReg = enum(u32) {
    Pmode    = 0x1200_0000,
    Smode1   = 0x1200_0010,
    Smode2   = 0x1200_0020,
    Srfsh    = 0x1200_0030,
    Synch1   = 0x1200_0040,
    Synch2   = 0x1200_0050,
    Syncv    = 0x1200_0060,
    Dispfb1  = 0x1200_0070,
    Display1 = 0x1200_0080,
    Dispfb2  = 0x1200_0090,
    Display2 = 0x1200_00A0,
    Extbuf   = 0x1200_00B0,
    Extdata  = 0x1200_00C0,
    Extwrite = 0x1200_00D0,
    Bgcolor  = 0x1200_00E0,
    GsCsr    = 0x1200_1000,
    GsImr    = 0x1200_1010,
    Busdir   = 0x1200_1040,
    Siglblid = 0x1200_1080,
    _
};

/// GS pixel formats
const PixelFormat = enum(u6) {
    Psmct32  = 0x00,
    Psmct24  = 0x01,
    Psmct16  = 0x02,
    Psmct16s = 0x0A,
    Psmct8   = 0x13,
    Psmct4   = 0x14,
    Psmct8h  = 0x1B,
    Psmct4hl = 0x24,
    Psmct4hh = 0x2C,
    Psmz32   = 0x30,
    Psmz24   = 0x31,
    Psmz16   = 0x32,
    Psmz16s  = 0x3A,

    /// Returns size of pixel format in bits
    pub fn getPixelSize(fmt: PixelFormat) u23 {
        return switch (fmt) {
            PixelFormat.Psmct32, PixelFormat.Psmz32   => 32,
            PixelFormat.Psmct24, PixelFormat.Psmz24   => 24,
            PixelFormat.Psmct16, PixelFormat.Psmct16s, PixelFormat.Psmz16, PixelFormat.Psmz16s => 16,
            PixelFormat.Psmct8 , PixelFormat.Psmct8h  =>  8,
            PixelFormat.Psmct4 , PixelFormat.Psmct4hl, PixelFormat.Psmct4hh => 4,
        };
    }
};

/// GS primitive
const Primitive = enum(u3) {
    Point,
    Line,
    LineStrip,
    Triangle,
    TriangleStrip,
    TriangleFan,
    Sprite,
    Reserved,

    /// Returns number of vertices required to draw the primitive
    pub fn getVtxCount(p: Primitive) usize {
        return switch (p) {
            Primitive.Point => 1,
            Primitive.Line, Primitive.LineStrip, Primitive.Sprite => 2,
            Primitive.Triangle, Primitive.TriangleStrip, Primitive.TriangleFan => 3,
            else => @panic("Reserved primitive"),
        };
    }
};

/// GS transmission direction
const Trxdir = enum(u2) {
    GifToVram,
    VramToGif,
    VramToVram,
    Off,
};

/// GS transmission parameters
const TrxParam = struct {
     srcBase: u23 = 0,
     srcSize: u23 = 0,
    srcWidth: u23 = 0,
        srcX: u23 = 0,
        srcY: u23 = 0,
     dstBase: u23 = 0,
     dstSize: u23 = 0,
    dstWidth: u23 = 0,
        dstX: u23 = 0,
        dstY: u23 = 0,
};

/// Texture coordinates
const St = struct {
    s: f32 = undefined,
    t: f32 = undefined,
};

/// Texel coordinates
const Uv = struct {
    u: u14 = undefined,
    v: u14 = undefined,
};

/// Vertex
const Vertex = struct {
    // Coordinates
    x: i23 = undefined,
    y: i23 = undefined,
    z: u32 = undefined,

    // Colors
    r: u8 = undefined,
    g: u8 = undefined,
    b: u8 = undefined,
    a: u8 = undefined,

    // Texel coordinates
    u: u14 = undefined,
    v: u14 = undefined,

    // Texture coordinates
    s: f32 = undefined,
    t: f32 = undefined,
    q: f32 = undefined,
};

/// Depth test
const ZTest = enum(u2) {
    Never,
    Always,
    GEqual,
    Greater,
};

/// --- GS internal registers

/// Alpha blending
const Alpha = struct {
      a: u2 = 0,
      b: u2 = 0,
      c: u2 = 0,
      d: u2 = 0,
    fix: u8 = 0,

    /// Sets ALPHA
    pub fn set(self: *Alpha, data: u64) void {
        self.a   = @truncate(u2, data >>  0);
        self.b   = @truncate(u2, data >>  2);
        self.c   = @truncate(u2, data >>  4);
        self.d   = @truncate(u2, data >>  6);
        self.fix = @truncate(u2, data >> 32);
    }
};

/// Bit blit buffer
const Bitbltbuf = struct {
     srcBase: u14 = 0,
    srcWidth: u6  = 0,
      srcFmt: PixelFormat = PixelFormat.Psmct32,
     dstBase: u14 = 0,
    dstWidth: u6  = 0,
      dstFmt: PixelFormat = PixelFormat.Psmct32,
    
    /// Sets BITBLTBUF
    pub fn set(self: *Bitbltbuf, data: u64) void {
        self.srcBase  = @truncate(u14, data);
        self.srcWidth = @truncate(u6 , data >> 16);
        self.srcFmt   = @intToEnum(PixelFormat, @truncate(u6, data >> 24));
        self.dstBase  = @truncate(u14, data >> 32);
        self.dstWidth = @truncate(u6 , data >> 48);
        self.dstFmt   = @intToEnum(PixelFormat, @truncate(u6, data >> 56));
    }
};

/// Frame buffer setting
const Frame = struct {
    fbp: u9 = 0,
    fbw: u6 = 0,
    psm: PixelFormat = PixelFormat.Psmct32,
    fbmsk: u32 = 0,

    /// Sets FRAME
    pub fn set(self: *Frame, data: u64) void {
        self.fbp   = @truncate(u9, data);
        self.fbw   = @truncate(u6, data >> 16);
        self.psm   = @intToEnum(PixelFormat, @truncate(u6, data >> 24));
        self.fbmsk = @truncate(u32, data >> 32);

        if (self.fbmsk != 0) @panic("Frame buffer mask is not 0");
    }
};

/// Primitive
const Prim = struct {
    prim: Primitive = Primitive.Reserved,
     iip: bool = false,
     tme: bool = false,
     fge: bool = false,
     abe: bool = false,
     aa1: bool = false,
     fst: bool = false,
    ctxt: bool = false,
     fix: bool = false,
    
    /// Sets PRIM
    pub fn set(self: *Prim, data: u64) void {
        self.prim = @intToEnum(Primitive, @truncate(u3, data));
        self.iip  = (data & (1 <<  3)) != 0;
        self.tme  = (data & (1 <<  4)) != 0;
        self.fge  = (data & (1 <<  5)) != 0;
        self.abe  = (data & (1 <<  6)) != 0;
        self.aa1  = (data & (1 <<  7)) != 0;
        self.fst  = (data & (1 <<  8)) != 0;
        self.ctxt = (data & (1 <<  9)) != 0;
        self.fix  = (data & (1 << 10)) != 0;
    }
};

/// TEST (incomplete)
const Test = struct {
     zte: bool  = false,
    ztst: ZTest = ZTest.Never,

    /// Sets TEST
    pub fn set(self: *Test, data: u64) void {
        if ((data & 1) != 0) {
            //@panic("Unhandled alpha testing");
        }
        if ((data & (1 << 14)) != 0) {
            //@panic("Unhandled destination alpha testing");
        }

        self.zte  = (data & (1 << 16)) != 0;
        self.ztst = @intToEnum(ZTest, @truncate(u2, data >> 17));
    }
};

/// RGBAQ
const Rgbaq = struct {
    r:  u8 = 0,
    g:  u8 = 0,
    b:  u8 = 0,
    a:  u8 = 0,
    q: f32 = 0,

    /// Sets RGBAQ
    pub fn set(self: *Rgbaq, data: u64) void {
        self.r = @truncate(u8 , data);
        self.g = @truncate(u8 , data >>  8);
        self.b = @truncate(u8 , data >> 16);
        self.a = @truncate(u8 , data >> 24);
        self.q = @bitCast(f32, @truncate(u32, data >> 32) & 0xFFFF_FF00);
    }
};

/// Scissor setting
const Scissor = struct {
    scax0: i23 = 0,
    scax1: i23 = 0,
    scay0: i23 = 0,
    scay1: i23 = 0,

    /// Sets SCISSOR
    pub fn set(self: *Scissor, data: u64) void {
        self.scax0 = @bitCast(i23, @as(u23, @truncate(u11, data >>  0))) << 4;
        self.scax1 = @bitCast(i23, @as(u23, @truncate(u11, data >> 16))) << 4;
        self.scay0 = @bitCast(i23, @as(u23, @truncate(u11, data >> 32))) << 4;
        self.scay1 = @bitCast(i23, @as(u23, @truncate(u11, data >> 48))) << 4;
    }
};

/// Texture information
const Tex = struct {
    tbp0: u14  = 0,
     tbw: u6   = 0,
     psm: PixelFormat = PixelFormat.Psmct32,
      tw: u4   = 0,
      th: u4   = 0,
     tcc: bool = false,
     tfx: u2   = 0,
     cbp: u14  = 0,
    cpsm: PixelFormat = PixelFormat.Psmct32,
     csm: bool = false,
     csa: u5   = 0,
     cld: u3   = 0,

    /// Sets TEX0
    pub fn setTex0(self: *Tex, data: u64) void {
        self.tbp0 = @truncate(u14, data);
        self.tbw  = @truncate(u6 , data >> 14);
        self.psm  = @intToEnum(PixelFormat, @truncate(u6, data >> 20));
        self.tw   = @truncate(u4 , data >> 26);
        self.th   = @truncate(u4 , data >> 30);
        self.tcc  = (data & (1 << 34)) != 0;
        self.tfx  = @truncate(u2 , data >> 35);
        self.cbp  = @truncate(u14, data >> 37);
        self.cpsm = @intToEnum(PixelFormat, @as(u6, @truncate(u4, data >> 51)));
        self.csm  = (data & (1 << 55)) != 0;
        self.csa  = @truncate(u5 , data >> 56);
        self.cld  = @truncate(u3 , data >> 61);
    }

    /// Sets TEX2
    pub fn setTex2(self: *Tex, data: u64) void {
        self.psm  = @intToEnum(PixelFormat, @truncate(u6, data >> 20));
        self.cbp  = @truncate(u14, data >> 37);
        self.cpsm = @intToEnum(PixelFormat, @as(u6, @truncate(u4, data >> 51)));
        self.csm  = (data & (1 << 55)) != 0;
        self.csa  = @truncate(u5 , data >> 56);
        self.cld  = @truncate(u3 , data >> 61);
    }
};

/// Texture alpha value
const Texa = struct {
    ta0: u8   = 0,
    aem: bool = false,
    ta1: u8   = 0,

    /// Sets TEXA
    pub fn set(self: *Texa, data: u64) void {
        self.ta0 = @truncate(u8, data);
        self.aem = (data & (1 << 15)) != 0;
        self.ta1 = @truncate(u8, data >> 32);
    }
};

/// Transmission position
const Trxpos = struct {
    srcX: u11 = 0,
    srcY: u11 = 0,
    dstX: u11 = 0,
    dstY: u11 = 0,
     dir: u2  = 0,

    /// Sets TRXPOS
    pub fn set(self: *Trxpos, data: u64) void {
        self.srcX = @truncate(u11, data);
        self.srcY = @truncate(u11, data >> 16);
        self.dstX = @truncate(u11, data >> 32);
        self.dstY = @truncate(u11, data >> 48);
        self.dir  = @truncate(u2 , data >> 59);
    }
};

/// Transmission register
const Trxreg = struct {
     width: u12 = 0,
    height: u12 = 0,

    /// Sets TRXREG
    pub fn set(self: *Trxreg, data: u64) void {
        self.width  = @truncate(u12, data);
        self.height = @truncate(u12, data >> 32);
    }
};

/// XY offset
const Xyoffset = struct {
    ofx: i23 = 0,
    ofy: i23 = 0,

    /// Sets XYOFFSET
    pub fn set(self: *Xyoffset, data: u64) void {
        self.ofx = @bitCast(i23, @as(u23, @truncate(u16, data >>  0)));
        self.ofy = @bitCast(i23, @as(u23, @truncate(u16, data >> 32)));
    }
};


/// Z buffer setting
const Zbuf = struct {
     zbp: u9   = 0,
     psm: PixelFormat = PixelFormat.Psmct32,
    zmsk: bool = false,

    /// Sets ZBUF
    pub fn set(self: *Zbuf, data: u64) void {
        self.zbp  = @truncate(u9, data);
        self.psm  = @intToEnum(PixelFormat, @truncate(u6, data >> 24));
        self.zmsk = (data & (1 << 32)) != 0;
    }
};

/// Control/Status Register
const Csr = struct {
    signal: bool = false,
    finish: bool = false,
     hsint: bool = false,
     vsint: bool = false,
    edwint: bool = false,
     field: bool = true,
      fifo: u2   = 1,
    
    /// Returns CSR
    pub fn get(self: Csr) u64 {
        var data: u64 = 0;

        data |= @as(u64, @bitCast(u1, self.signal));
        data |= @as(u64, @bitCast(u1, self.finish)) <<  1;
        data |= @as(u64, @bitCast(u1, self.hsint )) <<  2;
        data |= @as(u64, @bitCast(u1, self.vsint )) <<  3;
        data |= @as(u64, @bitCast(u1, self.edwint)) <<  4;
        data |= @as(u64, @bitCast(u1, !self.field)) << 12;
        data |= @as(u64, @bitCast(u1, self.field )) << 13;
        data |= @as(u64, self.fifo) << 14;
        data |= 0x1B << 16; // revision
        data |= 0x55 << 24; // ID

        return data;
    }

    /// Sets CSR
    pub fn set(self: *Csr, data: u64) void {
        if ((data & (1 << 0)) != 0) self.signal = false;
        if ((data & (1 << 1)) != 0) self.finish = false;
        if ((data & (1 << 2)) != 0) self.hsint  = false;
        if ((data & (1 << 3)) != 0) self.vsint  = false;
        if ((data & (1 << 4)) != 0) self.edwint = false;
    }
};

/// Interrupt Mask Register
const Imr = struct {
       sigmsk: bool = true, // SIGNAL mask
    finishmsk: bool = true, // FINISH mask
        hsmsk: bool = true, // HSYNC mask
        vsmsk: bool = true, // VSYNC mask
       edwmsk: bool = true, // Rectangular area write mask

    /// Returns IMR
    pub fn get(self: Imr) u64 {
        var data: u64 = 0;

        data |= @as(u64, @bitCast(u1, self.sigmsk)) << 8;
        data |= @as(u64, @bitCast(u1, self.sigmsk)) << 8;
        data |= @as(u64, @bitCast(u1, self.sigmsk)) << 8;
        data |= @as(u64, @bitCast(u1, self.sigmsk)) << 8;
        data |= @as(u64, @bitCast(u1, self.sigmsk)) << 8;

        return data;
    }
    
    /// Sets IMR
    pub fn set(self: *Imr, data: u64) void {
        self.sigmsk    = (data & (1 <<  8)) != 0;
        self.finishmsk = (data & (1 <<  9)) != 0;
        self.hsmsk     = (data & (1 << 10)) != 0;
        self.vsmsk     = (data & (1 << 11)) != 0;
        self.edwmsk    = (data & (1 << 12)) != 0;
    }
};

const  cyclesLine: i64 = 9371;
const cyclesFrame: i64 = cyclesLine * 60;

/// Simple Line counter
var cyclesToNextLine: i64 = 0;
var lines: i64 = 0;

const VertexQueue = LinearFifo(Vertex, LinearFifoBufferType{.Static = 3});

/// Vertex queue
var vtxQueue = VertexQueue.init();

// GS registers
var gsRegs: [0x63]u64 = undefined;

var       prim: Prim = Prim{};
var     prmode: Prim = Prim{};
var prmodecont: bool = false;

var rgbaq: Rgbaq = Rgbaq{};

var st: St = St{};
var uv: Uv = Uv{};

var  tex: [2]Tex = undefined;
var texa: Texa   = Texa{};

var    alpha: [2]Alpha = undefined;
var colclamp: bool     = false;

var xyoffset: [2]Xyoffset = undefined;
var  scissor: [2]Scissor  = undefined;

var frame: [2]Frame = undefined;
var  zbuf: [2]Zbuf  = undefined;
var test_: [2]Test  = undefined;

var bitbltbuf: Bitbltbuf = Bitbltbuf{};
var    trxpos: Trxpos    = Trxpos{};
var    trxreg: Trxreg    = Trxreg{};
var    trxdir: Trxdir    = Trxdir.Off;

// GS privileged registers
var csr: Csr = Csr{};
var imr: Imr = Imr{};

// Transmission parameters
var trxParam: TrxParam = TrxParam{};

var vram: []u32 = undefined;

/// Initializes the GS module
pub fn init(allocator: Allocator) !void {
    reset();

    vram = try allocator.alloc(u32, (2048 * 2048) / 4);
}

/// Deinitializes the GS module
pub fn deinit(allocator: Allocator) void {
    allocator.free(vram);
}

/// Resets the GS
fn reset() void {
    info("   [GS        ] GS reset.", .{});

    csr.set(0);
    imr.set(0xFF00);

    csr.fifo = 1;
}

/// Sets FINISH
pub fn setFinish() void {
    csr.finish = true;

    if (!imr.finishmsk) @panic("Unhandled FINISH interrupt");
}

/// Clears vertex queue, sets primitive vertex number
fn clearVtxQueue() void {
    vtxQueue = VertexQueue.init();
}

/// Reads data from a GS privileged register
pub fn readPriv(comptime T: type, addr: u32) T {
    if (!(T == u32 or T == u64)) {
        @panic("Unhandled read @ GS I/O");
    }

    var data: T = undefined;

    switch (addr) {
        @enumToInt(PrivReg.GsCsr) => {
            data = @truncate(T, csr.get());
        },
        else => {
            err("  [GS        ] Unhandled read ({s}) @ 0x{X:0>8} ({s}).", .{@typeName(T), addr, @tagName(@intToEnum(PrivReg, addr))});

            assert(false);
        }
    }

    //info("   [GS        ] Read ({s}) @ 0x{X:0>8} ({s}).", .{@typeName(T), addr, @tagName(@intToEnum(PrivReg, addr))});

    return data;
}

/// Reads data from local memory
pub fn readVram(comptime T: type, comptime psm: PixelFormat, base: u23, width: u23, x: u23, y: u23) T {
    var addr = switch (psm) {
        PixelFormat.Psmct32, PixelFormat.Psmz32  => base + width * y + x,
        PixelFormat.Psmct16, PixelFormat.Psmz16s => base + ((width * y) >> 1) + (x >> 1),
        else => {
            std.debug.print("Unhandled pixel storage mode: {s}\n", .{@tagName(psm)});

            @panic("Unhandled pixel format");
        }
    };

    addr &= 0xFF_FFF;

    return switch (psm) {
        PixelFormat.Psmct32, PixelFormat.Psmz32  => vram[addr],
        PixelFormat.Psmct16, PixelFormat.Psmz16s => @truncate(u16, vram[addr] >> (16 * @truncate(u5, x & 1))),
        else => {
            std.debug.print("Unhandled pixel storage mode: {s}\n", .{@tagName(psm)});

            @panic("Unhandled pixel format");
        }
    };
}

/// Writes data to a GS register
pub fn write(addr: u8, data: u64) void {
    if (addr > @enumToInt(GsReg.Label)) {
        std.debug.print("Invalid GS register 0x{X:0>2}\n", .{addr});

        @panic("Invalid GS register");
    }

    if (addr == 0x0F) {
        return std.debug.print("GS NOP\n", .{});
    }

    std.debug.print("Write @ {s} = 0x{X:0>16}\n", .{@tagName(@intToEnum(GsReg, addr)), data});

    switch (addr) {
        @enumToInt(GsReg.Prim      ) => {
            prim.set(data);

            clearVtxQueue();
        },
        @enumToInt(GsReg.Rgbaq     ) => rgbaq.set(data),
        @enumToInt(GsReg.St        ) => {
            st.s = @bitCast(f32, @truncate(u32, data >>  0) & 0xFFFF_FF00);
            st.t = @bitCast(f32, @truncate(u32, data >> 32) & 0xFFFF_FF00);
        },
        @enumToInt(GsReg.Uv        ) => {
            uv.u = @truncate(u14, data >>  0);
            uv.v = @truncate(u14, data >> 16);
        },
        @enumToInt(GsReg.Xyzf2     ),
        @enumToInt(GsReg.Xyz2      ), => {
            var vtx = Vertex{};

            vtx.x = @bitCast(i23, @as(u23, @truncate(u16, data >>  0)));
            vtx.y = @bitCast(i23, @as(u23, @truncate(u16, data >> 16)));

            if (addr == @enumToInt(GsReg.Xyzf2)) {
                vtx.z = @as(u32, @truncate(u24, data >> 32));
            } else {
                vtx.z = @as(u32, @truncate(u32, data >> 32));
            }

            // TODO: write fog value

            vtx.r = rgbaq.r;
            vtx.g = rgbaq.g;
            vtx.b = rgbaq.b;
            vtx.a = rgbaq.a;

            vtx.u = uv.u;
            vtx.v = uv.v;

            vtx.s = st.s;
            vtx.t = st.t;
            vtx.q = rgbaq.q;

            vtxQueue.writeItem(vtx) catch {
                err("  [GS        ] Vertex queue is full.", .{});
                
                assert(false);
            };

            const vtxCount = vtxQueue.readableLength();

            if (vtxCount == Primitive.getVtxCount(prim.prim)) {
                switch (prim.prim) {
                    Primitive.Point  => drawPoint(),
                    Primitive.Triangle, Primitive.TriangleStrip => drawTriangle(),
                    Primitive.Sprite => drawSprite(),
                    else => {
                        std.debug.print("Unsupported primitive: {s}\n", .{@tagName(prim.prim)});

                        @panic("Unsupported primitive");
                    }
                }

                if (prim.prim == Primitive.TriangleStrip) {
                    vtxQueue.discard(1);
                } else {
                    clearVtxQueue();
                }
            }
        },
        @enumToInt(GsReg.Tex01     ) => tex[0].setTex0(data),
        @enumToInt(GsReg.Tex02     ) => tex[1].setTex0(data),
        @enumToInt(GsReg.Tex21     ) => tex[0].setTex2(data),
        @enumToInt(GsReg.Tex22     ) => tex[1].setTex2(data),
        @enumToInt(GsReg.PrMode    ) => prmode.set(data),
        @enumToInt(GsReg.XyOffset1 ) => xyoffset[0].set(data),
        @enumToInt(GsReg.XyOffset2 ) => xyoffset[1].set(data),
        @enumToInt(GsReg.PrModeCont) => prmodecont = (data & 1) != 0,
        @enumToInt(GsReg.TexA      ) => texa.set(data),
        @enumToInt(GsReg.Scissor1  ) => scissor[0].set(data),
        @enumToInt(GsReg.Scissor2  ) => scissor[1].set(data),
        @enumToInt(GsReg.Alpha1    ) => alpha[0].set(data),
        @enumToInt(GsReg.Alpha2    ) => alpha[1].set(data),
        @enumToInt(GsReg.ColClamp  ) => colclamp = (data & 1) != 0,
        @enumToInt(GsReg.Test1     ) => test_[0].set(data),
        @enumToInt(GsReg.Test2     ) => test_[1].set(data),
        @enumToInt(GsReg.Pabe      ) => if ((data & 1) != 0) @panic("PABE"),
        @enumToInt(GsReg.Fba1      ) => if ((data & 1) != 0) @panic("FBA1"),
        @enumToInt(GsReg.Fba2      ) => if ((data & 1) != 0) @panic("FBA2"),
        @enumToInt(GsReg.Frame1    ) => frame[0].set(data),
        @enumToInt(GsReg.Frame2    ) => frame[1].set(data),
        @enumToInt(GsReg.Zbuf1     ) => zbuf[0].set(data),
        @enumToInt(GsReg.Zbuf2     ) => zbuf[1].set(data),
        @enumToInt(GsReg.BitBltBuf ) => bitbltbuf.set(data),
        @enumToInt(GsReg.TrxPos    ) => trxpos.set(data),
        @enumToInt(GsReg.TrxReg    ) => trxreg.set(data),
        @enumToInt(GsReg.TrxDir    ) => {
            trxdir = @intToEnum(Trxdir, @truncate(u2, data));

            if (trxdir != Trxdir.Off) {
                setupTransmission();

                if (trxdir == Trxdir.VramToVram) transmissionVramToVram();
            }
        },
        @enumToInt(GsReg.Hwreg ) => writeHwreg(data),
        @enumToInt(GsReg.Finish) => scheduleFinish(),
        else => {
            gsRegs[addr] = data;
        }
    }
}

/// Writes data to a GS register (from GIF)
pub fn writePacked(addr: u4, data: u128) void {
    switch (addr) {
        @enumToInt(GsReg.Prim) => {
            write(@enumToInt(GsReg.Prim), @truncate(u64, data));
        },
        @enumToInt(GsReg.Rgbaq) => {
            std.debug.print("Write @ Rgba = 0x{X:0>32}\n", .{data});

            rgbaq.r = @truncate(u8, data);
            rgbaq.g = @truncate(u8, data >> 32);
            rgbaq.b = @truncate(u8, data >> 64);
            rgbaq.a = @truncate(u8, data >> 96);
        },
        @enumToInt(GsReg.St) => {
            std.debug.print("Write @ Stq = 0x{X:0>32}\n", .{data});

            st.s = @bitCast(f32, @truncate(u32, data >>  0) & 0xFFFF_FF00);
            st.t = @bitCast(f32, @truncate(u32, data >> 32) & 0xFFFF_FF00);

            rgbaq.q = @bitCast(f32, @truncate(u32, data >> 64) & 0xFFFF_FF00);
        },
        @enumToInt(GsReg.Uv) => {
            const uv_ = @truncate(u64, ((data >> 16) & 0x3FFF_0000) | (data & 0x3FFF));

            write(@enumToInt(GsReg.Uv), uv_);
        },
        @enumToInt(GsReg.Xyzf2) => {
            var xyzf: u64 = 0;

            xyzf |= @as(u64, @truncate(u16, data));
            xyzf |= @as(u64, @truncate(u16, data >>  32)) << 16;
            xyzf |= @as(u64, @truncate(u24, data >>  68)) << 32;
            xyzf |= @as(u64, @truncate(u8 , data >> 100)) << 56;

            if ((data & (1 << 111)) != 0) {
                write(@enumToInt(GsReg.Xyzf3), xyzf);
            } else {
                write(@enumToInt(GsReg.Xyzf2), xyzf);
            }
        },
        @enumToInt(GsReg.Xyz2) => {
            var xyz: u64 = 0;

            xyz |= @as(u64, @truncate(u16, data));
            xyz |= @as(u64, @truncate(u16, data >>  32)) << 16;
            xyz |= @as(u64, @truncate(u32, data >>  64)) << 32;

            if ((data & (1 << 111)) != 0) {
                write(@enumToInt(GsReg.Xyz3), xyz);
            } else {
                write(@enumToInt(GsReg.Xyz2), xyz);
            }
        },
        @enumToInt(GsReg.Fog) => {
            const fog = @truncate(u64, data >> 40);

            write(@enumToInt(GsReg.Fog), fog);
        },
        @enumToInt(GsReg.AddrData) => {
            const reg = @truncate(u8, data >> 64);

            write(reg, @truncate(u64, data));
        },
        0x6, 0x8 => write(addr, @truncate(u64, data)),
        else => {
            err("  [GS        ] Unhandled PACKED write @ 0x{X} = 0x{X:0>32}.", .{addr, data});

            assert(false);
        }
    }
}

/// Writes data to HWREG
pub fn writeHwreg(data: u64) void {
    // std.debug.print("Write @ HWREG = 0x{X:0>16}\n", .{data});

    switch (trxdir) {
        Trxdir.GifToVram => transmissionGifToVram(data),
        Trxdir.Off       => {
            //std.debug.print("Transmission deactivated!\n", .{});
        },
        else => {
            std.debug.print("Unhandled transmission direction {s}\n", .{@tagName(trxdir)});

            @panic("Unhandled transmission direction");
        }
    }
}

var framePtr: u23 = 0;

/// Writes data to privileged register
pub fn writePriv(addr: u32, data: u64) void {
    switch (addr) {
        @enumToInt(PrivReg.GsCsr) => {
            if ((data & (1 << 9)) != 0) {
                reset();
            }

            csr.set(data);
        },
        @enumToInt(PrivReg.GsImr) => {
            imr.set(data);
        },
        @enumToInt(PrivReg.Dispfb1 ) => {
            std.debug.print("[GS        ] Write to Dispfb1 = 0x{X:0>16}\n", .{data});

            framePtr = 2048 * @as(u23, @truncate(u9, data));
        },
        @enumToInt(PrivReg.Dispfb2 ) => {
            std.debug.print("[GS        ] Write to Dispfb2 = 0x{X:0>16}\n", .{data});

            framePtr = 2048 * @as(u23, @truncate(u9, data));
        },
        @enumToInt(PrivReg.Pmode   ),
        @enumToInt(PrivReg.Smode1  ),
        @enumToInt(PrivReg.Smode2  ),
        @enumToInt(PrivReg.Srfsh   ),
        @enumToInt(PrivReg.Synch1  ),
        @enumToInt(PrivReg.Synch2  ),
        @enumToInt(PrivReg.Syncv   ),
        @enumToInt(PrivReg.Display1),
        @enumToInt(PrivReg.Display2),
        @enumToInt(PrivReg.Bgcolor ) => {},
        else => {
            err("  [GS        ] Unhandled write @ 0x{X:0>8} = 0x{X:0>16} ({s}).", .{addr, data, @tagName(@intToEnum(PrivReg, addr))});

            assert(false);
        }
    }

    info("   [GS        ] Write @ 0x{X:0>8} = 0x{X:0>16} ({s}).", .{addr, data, @tagName(@intToEnum(PrivReg, addr))});
}

/// Writes data to local memory
pub fn writeVram(comptime T: type, comptime psm: PixelFormat, base: u23, width: u23, x: u23, y: u23, data: T) void {
    //std.debug.print("Width = {}\n", .{width});

    var addr = switch (psm) {
        PixelFormat.Psmct32, PixelFormat.Psmz32, PixelFormat.Psmct4hh, PixelFormat.Psmct4hl => base + width * y + x,
        PixelFormat.Psmct24 => base + width * y + x,
        PixelFormat.Psmct16, PixelFormat.Psmz16s => base + ((width * y) >> 1) + (x >> 1),
        PixelFormat.Psmct8  => base + ((width * y) >> 2) + (x >> 2),
        else => {
            std.debug.print("Unhandled pixel storage mode: {s}\n", .{@tagName(psm)});

            @panic("Unhandled pixel format");
        }
    };

    addr &= 0xFF_FFF;

    switch (psm) {
        PixelFormat.Psmct32, PixelFormat.Psmz32  => vram[addr] = data,
        PixelFormat.Psmct24 => vram[addr] = (vram[addr] & 0xFF00_0000) | (data & 0xFF_FFFF),
        PixelFormat.Psmct16, PixelFormat.Psmz16s => {
            if ((x & 1) != 0) {
                vram[addr] = (vram[addr] & 0x0000_FFFF) | (@as(u32, data) << 16);
            } else {
                vram[addr] = (vram[addr] & 0xFFFF_0000) | (@as(u32, data) <<  0);
            }
        },
        PixelFormat.Psmct8 => {
            const vramData = vram[addr];

            const shift = 8 * @truncate(u5, x & 3);
            const mask  = ~(@as(u32, 0xFF) << shift);

            vram[addr] = (vramData & mask) | (@as(u32, data) << shift);
        },
        PixelFormat.Psmct4hh => vram[addr] = (vram[addr] & 0x0FFF_FFFF) | (@as(u32, data) << 28),
        PixelFormat.Psmct4hl => vram[addr] = (vram[addr] & 0xF0FF_FFFF) | (@as(u32, data) << 24),
        else => {
            std.debug.print("Unhandled pixel storage mode for write: {s}\n", .{@tagName(psm)});

            @panic("Unhandled pixel format");
        }
    }
}

/// Computes edge function
fn edgeFunction(a: Vertex, b: Vertex, c: Vertex) i64 {
    return (@as(i64, b.x) - @as(i64, a.x)) * (@as(i64, c.y) - @as(i64, a.y)) - (@as(i64, b.y) - @as(i64, a.y)) * (@as(i64, c.x) - @as(i64, a.x));
}

/// Performs alpha blending
fn alphaBlend(base: u23, x: u23, y: u23, color: u32) u32 {
    //std.debug.print("Alpha blend!\n", .{});

    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    const fbWidth = 64 * @as(u23, frame[ctxt].fbw);

    // Get current color from frame buffer
    const oldColor = readVram(u32, PixelFormat.Psmct32, base, fbWidth, x, y);

    var newColor: u32 = 0;

    var i: u5 = 0;
    while (i < 3) : (i += 1) {
        const oldCv = @truncate(u8, oldColor >> (8 * i));
        const newCv = @truncate(u8, color >> (8 * i));

        const A = switch (alpha[ctxt].a) {
            0 => newCv,
            1 => oldCv,
            2 => 0,
            3 => @panic("Reserved alpha blending setting"),
        };

        const B = switch (alpha[ctxt].b) {
            0 => newCv,
            1 => oldCv,
            2 => 0,
            3 => @panic("Reserved alpha blending setting"),
        };

        const C = switch (alpha[ctxt].c) {
            0 => @truncate(u8, color >> 24),
            1 => if (frame[ctxt].psm != PixelFormat.Psmct32) 0x80 else @truncate(u8, oldColor >> 24),
            2 => alpha[ctxt].fix,
            3 => @panic("Reserved alpha blending setting"),
        };

        const D = switch (alpha[ctxt].d) {
            0 => newCv,
            1 => oldCv,
            2 => 0,
            3 => @panic("Reserved alpha blending setting"),
        };

        var Cv = (((@bitCast(i32, @as(u32, A)) - @bitCast(i32, @as(u32, B))) * @bitCast(i32, @as(u32, C))) >> 7) + @bitCast(i32, @as(u32, D));

        if (colclamp) {
            if (Cv > 0xFF) {
                Cv = 0xFF;
            } else if (Cv < 0) {
                Cv = 0;
            }
        } else {
            Cv &= 0xFF;
        }

        newColor |= @as(u32, @truncate(u8, @bitCast(u32, Cv))) << (8 * i);
    }

    //std.debug.print("Alpha blending OK!\n", .{});

    return newColor | (color & 0xFF00_0000);
}

/// Performs a depth test
fn depthTest(x: i23, y: i23, depth: u32) bool {
    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    if (!test_[ctxt].zte) return true;

    const zAddr = 2048 * @as(u23, zbuf[ctxt].zbp);

    const zbWidth = 64 * @as(u23, frame[ctxt].fbw);

    var depth_ = depth;

    const oldDepth = switch (zbuf[ctxt].psm) {
        PixelFormat.Psmct32 , PixelFormat.Psmz32  => readVram(u32, PixelFormat.Psmz32 , zAddr, zbWidth, @bitCast(u23, x), @bitCast(u23, y)),
        PixelFormat.Psmct16s, PixelFormat.Psmz16s => readVram(u16, PixelFormat.Psmz16s, zAddr, zbWidth, @bitCast(u23, x), @bitCast(u23, y)),
        else => {
            std.debug.print("Unhandled Z buffer storage mode: {s}\n", .{@tagName(zbuf[ctxt].psm)});

            @panic("Unhandled pixel mode");
        }
    };

    switch (test_[ctxt].ztst) {
        ZTest.Never   => return false,
        ZTest.Always  => {},
        ZTest.GEqual  => {
            switch (zbuf[ctxt].psm) {
                PixelFormat.Psmct32 , PixelFormat.Psmz32  => if (depth_ < oldDepth) return false,
                PixelFormat.Psmct16s, PixelFormat.Psmz16s => {
                    depth_ = @truncate(u16, min(u32, depth_, 0xFFFF));

                    if (depth_ < oldDepth) return false;
                },
                else => {
                    std.debug.print("Unhandled Z buffer storage mode: {s}\n", .{@tagName(zbuf[ctxt].psm)});

                    @panic("Unhandled pixel mode");
                }
            }
        },
        ZTest.Greater => {
            switch (zbuf[ctxt].psm) {
                PixelFormat.Psmct32 , PixelFormat.Psmz32  => if (depth_ <= oldDepth) return false,
                PixelFormat.Psmct16s, PixelFormat.Psmz16s => {
                    depth_ = @truncate(u16, min(u32, depth_, 0xFFFF));

                    if (depth_ <= oldDepth) return false;
                },
                else => {
                    std.debug.print("Unhandled Z buffer storage mode: {s}\n", .{@tagName(zbuf[ctxt].psm)});

                    @panic("Unhandled pixel mode");
                }
            }
        }
    }

    if (!zbuf[ctxt].zmsk) {
        switch (zbuf[ctxt].psm) {
            PixelFormat.Psmct32 , PixelFormat.Psmz32  => writeVram(u32, PixelFormat.Psmz32 , zAddr, zbWidth, @bitCast(u23, x), @bitCast(u23, y), depth_),
            PixelFormat.Psmct16s, PixelFormat.Psmz16s => writeVram(u16, PixelFormat.Psmz16s, zAddr, zbWidth, @bitCast(u23, x), @bitCast(u23, y), @truncate(u16, depth_)),
            else => {
                std.debug.print("Unhandled Z buffer storage mode: {s}\n", .{@tagName(zbuf[ctxt].psm)});

                @panic("Unhandled pixel mode");
            }
        }
    }

    return true;
}

/// Calculates Z
fn getDepth(a: Vertex, b: Vertex, c: Vertex, w0: i64, w1: i64, w2: i64) u32 {
    const area = edgeFunction(a, b, c);

    const az = @as(i64, @bitCast(i32, a.z));
    const bz = @as(i64, @bitCast(i32, b.z));
    const cz = @as(i64, @bitCast(i32, c.z));

    const z = @divTrunc((w0 * az) + (w1 * bz) + (w2 * cz), area);

    return @bitCast(u32, @truncate(i32, z));
}

/// Calculates RGBA
fn getColor(a: Vertex, b: Vertex, c: Vertex, w0: i64, w1: i64, w2: i64) u32 {
    const area = edgeFunction(a, b, c);

    const colorA = @as(i64, @bitCast(i32, (@as(u32, a.a) << 24) | (@as(u32, a.b) << 16) | (@as(u32, a.g) << 8) | (@as(u32, a.r))));
    const colorB = @as(i64, @bitCast(i32, (@as(u32, b.a) << 24) | (@as(u32, b.b) << 16) | (@as(u32, b.g) << 8) | (@as(u32, b.r))));
    const colorC = @as(i64, @bitCast(i32, (@as(u32, c.a) << 24) | (@as(u32, c.b) << 16) | (@as(u32, c.g) << 8) | (@as(u32, c.r))));

    const color = @divTrunc((w0 * colorA) + (w1 * colorB) + (w2 * colorC), area);

    return @bitCast(u32, @truncate(i32, color));
}

/// Interpolate STQ
fn getTexCoord(a: f32, b: f32, c: f32, w0: i64, w1: i64, w2: i64) f32 {
    //std.debug.print("W0 = {}, W1 = {}, W2 = {}\n", .{@intToFloat(f32, w0), @intToFloat(f32, w1), @intToFloat(f32, w2)});
    //std.debug.print("Area = {}\n", .{@intToFloat(f32, area)});

    const texCoord = @intToFloat(f32, w0) * a + @intToFloat(f32, w1) * b + @intToFloat(f32, w2) * c;

    //std.debug.print("Tex coord = {}\n", .{texCoord});

    return texCoord;
}

/// Taken from https://github.com/PSI-Rockin/DobieStation
/// Interpolate UV
fn getUv(x: i64, u1_: u14, x1: i64, u2_: u14, x2: i64) i64 {
    var temp = @bitCast(i64, @as(u64, u1_)) * (x2 - x);

    temp += @bitCast(i64, @as(u64, u2_)) * (x - x1);

    if ((x2 - x1) == 0) return @bitCast(i64, @as(u64, u1_));

    return @divTrunc(temp, x2 - x1);
}

/// Interpolate ST
fn getSt(x: i32, s1: f32, x1: i32, s2: f32, x2: i32) f32 {
    var temp = s1 * @intToFloat(f32, x2 - x);

    temp += s2 * @intToFloat(f32, x - x1);

    if ((x2 - x1) == 0) return s1;

    return temp / @intToFloat(f32, x2 - x1);
}

/// Taken from https://github.com/PSI-Rockin/DobieStation
/// Returns UV step
fn getUvStep(u1_: u14, x1: i64, u2_: u14, x2: i64, m: i64) i64 {
    if ((x2 - x1) == 0) return (@bitCast(i64, @as(u64, u2_)) - @bitCast(i64, @as(u64, u1_))) * m;

    std.debug.print("UV step OK!\n", .{});

    return @divTrunc((@bitCast(i64, @as(u64, u2_)) - @bitCast(i64, @as(u64, u1_))) * m, x2 - x1);
}

/// Returns ST step
fn getStStep(s1: f32, x1: i32, s2: f32, x2: i32, m: i32) f32 {
    if ((x2 - x1) == 0) return (s2 - s1) * @intToFloat(f32, m);

    std.debug.print("ST step OK!\n", .{});

    return ((s2 - s1) * @intToFloat(f32, m)) / @intToFloat(f32, x2 - x1);
}

/// Returns a texture pixel (UV coordinates)
fn getTex(u: u14, v: u14) u32 {
    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    const texAddr  = 64 * @as(u23, tex[ctxt].tbp0);
    const clutAddr = 64 * @as(u23, tex[ctxt].cbp );

    const tbWidth = 64 * @as(u23, tex[ctxt].tbw);

    const csa = tex[ctxt].csa;

    if (csa != 0) @panic("Unhandled CLUT offset");

    var color: u32 = 0;

    switch (tex[ctxt].psm) {
        PixelFormat.Psmct32 => {
            color = readVram(u32, PixelFormat.Psmct32, texAddr, tbWidth, u, v);
        },
        PixelFormat.Psmct24 => {
            color = (@as(u32, texa.ta0) << 24) | (readVram(u32, PixelFormat.Psmct32, texAddr, tbWidth, u, v) & 0xFF_FFFF);
        },
        PixelFormat.Psmct4hl, PixelFormat.Psmct4hh => {
            var idtex4 = @truncate(u23, readVram(u32, PixelFormat.Psmct32, texAddr, tbWidth, u, v) >> 24);

            if (tex[ctxt].psm == PixelFormat.Psmct4hl) {
                idtex4 &= 0xF;
            } else {
                idtex4 >>= 4;
            }

            // Get color from CLUT
            switch (tex[ctxt].cpsm) {
                PixelFormat.Psmct32 => {
                    if (tex[ctxt].csm) {
                        //color = readVram(u32, PixelFormat.Psmct32, clutAddr, 0, idtex4);
                        @panic("Invalid CLUT CSM2 pixel format");
                    }

                    color = readVram(u32, PixelFormat.Psmct32, clutAddr, 1024, idtex4 >> 3, idtex4 & 7);
                },
                PixelFormat.Psmct16 => {
                    const texColor = switch (tex[ctxt].csm) {
                         true => readVram(u16, PixelFormat.Psmct16, clutAddr, 1024, 0, idtex4),
                        false => readVram(u16, PixelFormat.Psmct16, clutAddr, 1024, idtex4 >> 3, idtex4 & 7),
                    };

                    const r = @truncate(u5, texColor >>  0);
                    const g = @truncate(u5, texColor >>  5);
                    const b = @truncate(u5, texColor >> 10);

                    color = (@as(u32, b) << 19) | (@as(u32, g) << 11) | (@as(u32, r) << 3);

                    if (!(texa.aem and color == 0)) {
                        if ((texColor & (1 << 15)) != 0) {
                            color |= @as(u32, texa.ta1) << 24;
                        } else {
                            color |= @as(u32, texa.ta0) << 24;
                        }
                    }
                },
                else => {
                    std.debug.print("Unhandled CLUT storage mode: {s}\n", .{@tagName(tex[ctxt].cpsm)});

                    @panic("Unhandled pixel format");
                }
            }
        },
        else => {
            std.debug.print("Unhandled texture storage mode: {s}\n", .{@tagName(tex[ctxt].psm)});

            @panic("Unhandled pixel format");
        }
    }

    return color;
}

/// Texture-vertex alpha addition
fn texAdd(Av: u8, At: u8) u8 {
    if (Av == 0x80) return At;

    var res = @bitCast(i16, @as(u16, Av)) + @bitCast(i16, @as(u16, At));

    if (res > 0xFF) {
        res = 0xFF;
    } else if (res < 0) {
        res = 0;
    }

    return @truncate(u8, @bitCast(u16, res));
}

/// Texture-vertex color multiplication
fn texMul(Cv: u8, Ct: u8) u8 {
    if (Cv == 0x80) return Ct;

    var res = (@bitCast(i16, @as(u16, Cv)) * @bitCast(i16, @as(u16, Ct))) >> 7;

    if (res > 0xFF) {
        res = 0xFF;
    } else if (res < 0) {
        res = 0;
    }

    return @truncate(u8, @bitCast(u16, res));
}

/// Texture-vertex color multiply-add
fn texMulAdd(Cv: u8, Ct: u8, Av: u8) u8 {
    if (Cv == 0x80) return Ct;

    var res = ((@bitCast(i16, @as(u16, Cv)) * @bitCast(i16, @as(u16, Ct))) >> 7) + @bitCast(i16, @as(u16, Av));

    if (res > 0xFF) {
        res = 0xFF;
    } else if (res < 0) {
        res = 0;
    }

    return @truncate(u8, @bitCast(u16, res));
}

/// Draws a point
fn drawPoint() void {
    std.debug.print("Drawing point...\n", .{});

    var a = vtxQueue.peekItem(0);

    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    const ofx = xyoffset[ctxt].ofx;
    const ofy = xyoffset[ctxt].ofy;

    // Offset coordinates
    a.x -= ofx;
    a.y -= ofy;

    a.x >>= 4;
    a.y >>= 4;

    const scax0 = scissor[ctxt].scax0 >> 4;
    const scax1 = (scissor[ctxt].scax1 >> 4) + 1;
    const scay0 = scissor[ctxt].scay0 >> 4;
    const scay1 = (scissor[ctxt].scay1 >> 4) + 1;

    const fbAddr = 2048 * @as(u23, frame[ctxt].fbp);

    const fbWidth = 64 * @as(u23, frame[ctxt].fbw);
    
    std.debug.print("a = [{};{}]\n", .{a.x, a.y});

    std.debug.print("Frame buffer address = 0x{X:0>6}, OFX = {}, OFY = {}\n", .{fbAddr, ofx >> 4, ofy >> 4});
    std.debug.print("SCAX0 = {}, SCAX1 = {}, SCAY0 = {}, SCAY1 = {}\n", .{scax0, scax1, scay0, scay1});

    if ((a.x < scax0) or (a.x > scax1) or (a.y < scay0) or (a.y > scay1)) return;

    const tme = if (prmodecont) prim.tme else prmode.tme;
    const abe = if (prmodecont) prim.abe else prmode.abe;

    if (tme) {
        const fst = if (prmodecont) prim.fst else prmode.fst;

        if (!fst) {
            std.debug.print("Unhandled STQ coordinates\n", .{});

            @panic("Unhandled texture coordinates");
        }

        std.debug.print("Unhandled texturing\n", .{});

        @panic("Unhandled texturing");
    }

    var color = (@as(u32, a.a) << 24) | (@as(u32, a.b) << 16) | (@as(u32, a.g) << 8) | @as(u32, a.r);

    if (abe) color = alphaBlend(fbAddr, @bitCast(u23, a.x), @bitCast(u23, a.y), color);

    if (!depthTest(a.x, a.y, a.z)) return;

    switch (frame[ctxt].psm) {
        PixelFormat.Psmct32 => writeVram(u32, PixelFormat.Psmct32, fbAddr, fbWidth, @bitCast(u23, a.x), @bitCast(u23, a.y), color),
        PixelFormat.Psmct24 => writeVram(u32, PixelFormat.Psmct24, fbAddr, fbWidth, @bitCast(u23, a.x), @bitCast(u23, a.y), color),
        else => {
            std.debug.print("Unhandled frame buffer storage mode: {s}\n", .{@tagName(frame[ctxt].psm)});

            @panic("Unhandled pixel storage mode");
        }
    }
}

/// Draws a sprite
fn drawSprite() void {
    std.debug.print("Drawing sprite...\n", .{});

    var a = vtxQueue.peekItem(0);
    var b = vtxQueue.peekItem(1);

    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    const ofx = xyoffset[ctxt].ofx;
    const ofy = xyoffset[ctxt].ofy;

    // Offset coordinates
    a.x -= ofx;
    b.x -= ofx;
    a.y -= ofy;
    b.y -= ofy;

    const fbAddr = 2048 * @as(u23, frame[ctxt].fbp);

    const fbWidth = 64 * @as(u23, frame[ctxt].fbw);

    const scax0 = scissor[ctxt].scax0;
    const scax1 = scissor[ctxt].scax1;
    const scay0 = scissor[ctxt].scay0;
    const scay1 = scissor[ctxt].scay1;

    const xMin = (max(i23, min(i23, a.x, b.x), scax0) >> 4) << 4;
    const xMax = (min(i23, max(i23, a.x, b.x), (scax1 + 0x10)) >> 4) << 4;
    const yMin = (max(i23, min(i23, a.y, b.y), scay0) >> 4) << 4;
    const yMax = (min(i23, max(i23, a.y, b.y), (scay1 + 0x10)) >> 4) << 4;
    
    std.debug.print("a = [{};{}], b = [{};{}]\n", .{xMin >> 4, yMin >> 4, xMax >> 4, yMax >> 4});

    std.debug.print("Frame buffer address = 0x{X:0>6}, OFX = {}, OFY = {}\n", .{fbAddr, ofx >> 4, ofy >> 4});
    std.debug.print("SCAX0 = {}, SCAX1 = {}, SCAY0 = {}, SCAY1 = {}\n", .{scax0 >> 4, (scax1 >> 4) + 1, scay0 >> 4, (scay1 >> 4) + 1});

    const tme = if (prmodecont) prim.tme else prmode.tme;
    const abe = if (prmodecont) prim.abe else prmode.abe;
    const fst = if (prmodecont) prim.fst else prmode.fst;

    const uStart = getUv(xMin, a.u, a.x, b.u, b.x) << 16;
    const vStart = getUv(yMin, a.v, a.y, b.v, b.y) << 16;

    const sStart = getSt(xMin, a.s, a.x, b.s, b.x);
    const tStart = getSt(xMin, a.t, a.y, b.t, b.y);

    std.debug.print("U = {}, V = {}, S = {}, T = {}\n", .{uStart >> 20, vStart >> 20, sStart, tStart});

    const uStep = getUvStep(a.u, a.x, b.u, b.x, 0x100000);
    const vStep = getUvStep(a.v, a.y, b.v, b.y, 0x100000);

    const sStep = getStStep(a.s, a.x, b.s, b.x, 0x10);
    const tStep = getStStep(a.t, a.y, b.t, b.y, 0x10);

    std.debug.print("Ustep = {}, Vstep = {}\n", .{uStep >> 20, vStep >> 20});

    var y = yMin >> 4;
    var v = vStart;
    var t = tStart;
    while (y < (yMax >> 4)) : (y += 1) {
        var x = xMin >> 4;
        var u = uStart;
        var s = sStart;
        while (x < (xMax >> 4)) : (x += 1) {
            var color: u32 = 0;

            if (tme) {
                const texU = if (fst) @truncate(u14, @bitCast(u64, u >> 16)) else @truncate(u14, @floatToInt(u32, ((s / a.q) * @intToFloat(f32, @as(u16, 1) << tex[ctxt].tw)) * 16.0));
                const texV = if (fst) @truncate(u14, @bitCast(u64, v >> 16)) else @truncate(u14, @floatToInt(u32, ((t / a.q) * @intToFloat(f32, @as(u16, 1) << tex[ctxt].th)) * 16.0));

                const texColor = getTex(texU >> 4, texV >> 4);

                switch (tex[ctxt].tfx) {
                //switch (@as(u2, 1)) {
                    0 => {
                        // Modulate
                        color |= @as(u32, texMul(a.r, @truncate(u8, texColor >>  0)));
                        color |= @as(u32, texMul(a.g, @truncate(u8, texColor >>  8))) <<  8;
                        color |= @as(u32, texMul(a.b, @truncate(u8, texColor >> 16))) << 16;

                        if (tex[ctxt].tcc) {
                            color |= @as(u32, texMul(a.a, @truncate(u8, texColor >> 24))) << 24;
                        } else {
                            color |= @as(u32, a.a) << 24;
                        }
                    },
                    1 => {
                        // Decal
                        color = texColor & 0xFF_FFFF;

                        if (tex[ctxt].tcc) {
                            color |= texColor & 0xFF00_0000;
                        } else {
                            color |= @as(u32, a.a) << 24;
                        }
                    },
                    2 => {
                        // Highlight
                        color |= @as(u32, texMulAdd(a.r, @truncate(u8, texColor >>  0), a.a));
                        color |= @as(u32, texMulAdd(a.g, @truncate(u8, texColor >>  8), a.a)) <<  8;
                        color |= @as(u32, texMulAdd(a.b, @truncate(u8, texColor >> 16), a.a)) << 16;

                        if (tex[ctxt].tcc) {
                            color |= @as(u32, texAdd(a.a, @truncate(u8, texColor >> 24))) << 24;
                        } else {
                            color |= @as(u32, a.a) << 24;
                        }
                    },
                    3 => {
                        // Highlight2
                        color |= @as(u32, texMulAdd(a.r, @truncate(u8, texColor >>  0), a.a));
                        color |= @as(u32, texMulAdd(a.g, @truncate(u8, texColor >>  8), a.a)) <<  8;
                        color |= @as(u32, texMulAdd(a.b, @truncate(u8, texColor >> 16), a.a)) << 16;

                        if (tex[ctxt].tcc) {
                            color |= texColor & 0xFF00_0000;
                        } else {
                            color |= @as(u32, a.a) << 24;
                        }
                    }
                }
            } else {
                color = (@as(u32, a.a) << 24) | (@as(u32, a.b) << 16) | (@as(u32, a.g) << 8) | @as(u32, a.r);
            }

            if (abe) color = alphaBlend(fbAddr, @bitCast(u23, x), @bitCast(u23, y), color);

            if (!depthTest(x, y, a.z)) {
                u += uStep;
                s += sStep;

                continue;
            }

            switch (frame[ctxt].psm) {
                PixelFormat.Psmct32 => writeVram(u32, PixelFormat.Psmct32, fbAddr, fbWidth, @bitCast(u23, x), @bitCast(u23, y), color),
                PixelFormat.Psmct24 => writeVram(u32, PixelFormat.Psmct24, fbAddr, fbWidth, @bitCast(u23, x), @bitCast(u23, y), color),
                else => {
                    std.debug.print("Unhandled frame buffer storage mode: {s}\n", .{@tagName(frame[ctxt].psm)});

                    @panic("Unhandled pixel storage mode");
                }
            }

            u += uStep;
            s += sStep;
        }

        v += vStep;
        t += tStep;
    }
}

/// Draws a triangle
fn drawTriangle() void {
    std.debug.print("Drawing triangle...\n", .{});

    var a = vtxQueue.peekItem(0);
    var b = vtxQueue.peekItem(1);
    var c = vtxQueue.peekItem(2);

    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    const ofx = xyoffset[ctxt].ofx;
    const ofy = xyoffset[ctxt].ofy;

    // Offset coordinates
    a.x -= ofx;
    b.x -= ofx;
    c.x -= ofx;
    a.y -= ofy;
    b.y -= ofy;
    c.y -= ofy;

    a.x = @as(i23, @truncate(i12, a.x >> 4));
    b.x = @as(i23, @truncate(i12, b.x >> 4));
    c.x = @as(i23, @truncate(i12, c.x >> 4));
    a.y = @as(i23, @truncate(i12, a.y >> 4));
    b.y = @as(i23, @truncate(i12, b.y >> 4));
    c.y = @as(i23, @truncate(i12, c.y >> 4));

    std.debug.print("a = [{};{}], b = [{};{}], c = [{};{}]\n", .{a.x, a.y, b.x, b.y, c.x, c.y});

    var p  = Vertex{};
    var b_ = Vertex{};
    var c_ = Vertex{};

    if ((edgeFunction(a, b, c)) < 0) {
        b_ = c;
        c_ = b;
    } else {
        b_ = b;
        c_ = c;
    }

    const fbAddr = 2048 * @as(u23, frame[ctxt].fbp);

    const fbWidth = 64 * @as(u23, frame[ctxt].fbw);

    const scax0 = scissor[ctxt].scax0 >> 4;
    const scax1 = (scissor[ctxt].scax1 >> 4) + 1;
    const scay0 = scissor[ctxt].scay0 >> 4;
    const scay1 = (scissor[ctxt].scay1 >> 4) + 1;

    std.debug.print("Frame buffer address = 0x{X:0>6}, OFX = {}, OFY = {}\n", .{fbAddr, ofx >> 4, ofy >> 4});
    std.debug.print("SCAX0 = {}, SCAX1 = {}, SCAY0 = {}, SCAY1 = {}\n", .{scax0, scax1, scay0, scay1});

    const tme = if (prmodecont) prim.tme else prmode.tme;
    const abe = if (prmodecont) prim.abe else prmode.abe;

    if (tme) {
        const fst = if (prmodecont) prim.fst else prmode.fst;

        if (fst) {
            std.debug.print("Unhandled UV coordinates\n", .{});

            @panic("Unhandled texture coordinates");
        }
    }

    // Calculate bounding box
    var xMin = min(i23, min(i23, a.x, b.x), c.x);
    var yMin = min(i23, min(i23, a.y, b.y), c.y);
    var xMax = max(i23, max(i23, a.x, b.x), c.x);
    var yMax = max(i23, max(i23, a.y, b.y), c.y);

    xMin = max(i23, xMin, scax0);
    yMin = max(i23, yMin, scay0);
    xMax = min(i23, xMax, scax1);
    yMax = min(i23, yMax, scay1);

    p.y = yMin;
    while (p.y < yMax) : (p.y += 1) {
        p.x = xMin;
        while (p.x < xMax) : (p.x += 1) {
            const w0 = edgeFunction(b_, c_, p);
            const w1 = edgeFunction(c_, a , p);
            const w2 = edgeFunction(a , b_, p);

            //std.debug.print("w0 = {}, w1 = {}, w2 = {}\n", .{w0, w1, w2});

            if (w0 >= 0 and w1 >= 0 and w2 >= 0) {
                p.z = getDepth(a, b_, c_, w0, w1, w2);

                if (!depthTest(p.x, p.y, p.z)) continue;

                var color: u32 = 0;

                if (tme) {
                    //std.debug.print("S1 = {}, S2 = {}, S3 = {}\n", .{a.s, b_.s, c_.s});
                    //std.debug.print("T1 = {}, T2 = {}, T3 = {}\n", .{a.t, b_.t, c_.t});
                    //std.debug.print("Q1 = {}, Q2 = {}, Q3 = {}\n", .{a.q, b_.q, c_.q});

                    var s = getTexCoord(a.s, b_.s, c_.s, w0, w1, w2);
                    var t = getTexCoord(a.t, b_.t, c_.t, w0, w1, w2);

                    const q = getTexCoord(a.q, b_.q, c_.q, w0, w1, w2);

                    //std.debug.print("S = {}, T = {}, Q = {}\n", .{s, t, q});

                    s /= q;
                    t /= q;

                    //std.debug.print("S/Q = {}, T/Q = {}\n", .{s, t});

                    const u = @truncate(u14, @floatToInt(u32, (s * @intToFloat(f32, @as(u16, 1) << tex[ctxt].tw)) * 16.0));
                    const v = @truncate(u14, @floatToInt(u32, (t * @intToFloat(f32, @as(u16, 1) << tex[ctxt].th)) * 16.0));

                    //std.debug.print("U = {}, V = {}\n", .{(u >> 4) % (@as(u14, 1) << tex[ctxt].tw), (v >> 4) % (@as(u14, 1) << tex[ctxt].th)});

                    const texColor = getTex((u >> 4) % (@as(u14, 1) << tex[ctxt].tw), (v >> 4) % (@as(u14, 1) << tex[ctxt].th));

                    //std.debug.print("Ct = 0x{X:0>8}\n", .{texColor});

                    switch (tex[ctxt].tfx) {
                        0 => {
                            // Modulate
                            color |= @as(u32, texMul(a.r, @truncate(u8, texColor >>  0)));
                            color |= @as(u32, texMul(a.g, @truncate(u8, texColor >>  8))) <<  8;
                            color |= @as(u32, texMul(a.b, @truncate(u8, texColor >> 16))) << 16;

                            if (tex[ctxt].tcc) {
                                color |= @as(u32, texMul(a.a, @truncate(u8, texColor >> 24))) << 24;
                            } else {
                                color |= @as(u32, a.a) << 24;
                            }
                        },
                        1 => {
                            // Decal
                            color = texColor & 0xFF_FFFF;

                            if (tex[ctxt].tcc) {
                                color |= texColor & 0xFF00_0000;
                            } else {
                                color |= @as(u32, a.a) << 24;
                            }
                        },
                        2 => {
                            // Highlight
                            color |= @as(u32, texMul(a.r, @truncate(u8, texColor >>  0)) +| a.a);
                            color |= @as(u32, texMul(a.g, @truncate(u8, texColor >>  8)) +| a.a) <<  8;
                            color |= @as(u32, texMul(a.b, @truncate(u8, texColor >> 16)) +| a.a) << 16;

                            if (tex[ctxt].tcc) {
                                color |= @as(u32, a.a +| @truncate(u8, texColor >> 24)) << 24;
                            } else {
                                color |= @as(u32, a.a) << 24;
                            }
                        },
                        3 => {
                            // Highlight2
                            color |= @as(u32, texMul(a.r, @truncate(u8, texColor >>  0)) +| a.a);
                            color |= @as(u32, texMul(a.g, @truncate(u8, texColor >>  8)) +| a.a) <<  8;
                            color |= @as(u32, texMul(a.b, @truncate(u8, texColor >> 16)) +| a.a) << 16;

                            if (tex[ctxt].tcc) {
                                color |= texColor & 0xFF00_0000;
                            } else {
                                color |= @as(u32, a.a) << 24;
                            }
                        }
                    }

                    //std.debug.print("Tex blending OK!!\n", .{});
                } else {
                    color = getColor(a, b_, c_, w0, w1, w2);
                }

                if (abe) color = alphaBlend(fbAddr, @bitCast(u23, p.x), @bitCast(u23, p.y), color);

                //std.debug.print("Alpha blending OK!!\n", .{});

                switch (frame[ctxt].psm) {
                    PixelFormat.Psmct32 => writeVram(u32, PixelFormat.Psmct32, fbAddr, fbWidth, @bitCast(u23, p.x), @bitCast(u23, p.y), color),
                    PixelFormat.Psmct24 => writeVram(u32, PixelFormat.Psmct24, fbAddr, fbWidth, @bitCast(u23, p.x), @bitCast(u23, p.y), color),
                    else => {
                        std.debug.print("Unhandled frame buffer storage mode: {s}\n", .{@tagName(frame[ctxt].psm)});

                        @panic("Unhandled pixel storage mode");
                    }
                }

                //std.debug.print("X = {}, Y = {}\n", .{p.x, p.y});
                //std.debug.print("Addr = 0x{X:0>6}\n", .{fbAddr + 1024 * @bitCast(u16, p.y) + @bitCast(u16, p.x)});
            }
        }
    }
}

/// Sets up variables used for local memory transmission
fn setupTransmission() void {
    switch (trxdir) {
        Trxdir.GifToVram => {
            std.debug.print("Setting up GIF->VRAM transmission...\n", .{});

            const dstSize = PixelFormat.getPixelSize(bitbltbuf.dstFmt);

            if (dstSize == 4) {
                switch (bitbltbuf.dstFmt) {
                    PixelFormat.Psmct4hh, PixelFormat.Psmct4hl => {},
                    else => {
                        std.debug.print("Unhandled 4-bit pixel format: {s}\n", .{@tagName(bitbltbuf.dstFmt)});

                        @panic("Unhandled 4-bit pixel format");
                    }
                }
            }

            trxParam.dstSize = dstSize;

            trxParam.dstBase  = 64 * @as(u23, bitbltbuf.dstBase);
            trxParam.dstWidth = 64 * @as(u23, bitbltbuf.dstWidth);

            trxParam.dstX = 0;
            trxParam.dstY = 0;
            
            std.debug.print("Destination base = 0x{X:0>6}, width = {}, X = {}, Y = {}, Format = {s}\n", .{trxParam.dstBase, trxParam.dstWidth, trxpos.dstX, trxpos.dstY, @tagName(bitbltbuf.dstFmt)});
        },
        Trxdir.VramToGif => {
            std.debug.print("Unhandled VRAM->GIF transfer\n", .{});

            @panic("Unhandled VRAM->GIF transfer");
        },
        Trxdir.VramToVram => {
            std.debug.print("Setting up VRAM->VRAM transmission...\n", .{});

            const srcSize = PixelFormat.getPixelSize(bitbltbuf.srcFmt);
            const dstSize = PixelFormat.getPixelSize(bitbltbuf.dstFmt);

            if (srcSize != 32) {
                std.debug.print("Unhandled source pixel format: {s}\n", .{@tagName(bitbltbuf.srcFmt)});

                @panic("Unhandled source pixel format");
            }
            if (dstSize != 32) {
                std.debug.print("Unhandled destination pixel format: {s}\n", .{@tagName(bitbltbuf.dstFmt)});

                @panic("Unhandled destination pixel format");
            }

            if (srcSize != dstSize) {
                std.debug.print("Pixel sizes don't match\n", .{});

                @panic("Pixel sizes don't match");
            }

            trxParam.srcSize = srcSize;
            trxParam.dstSize = dstSize;

            trxParam.srcBase  = 64 * @as(u23, bitbltbuf.srcBase);
            trxParam.srcWidth = 64 * @as(u23, bitbltbuf.srcWidth);
            trxParam.dstBase  = 64 * @as(u23, bitbltbuf.dstBase);
            trxParam.dstWidth = 64 * @as(u23, bitbltbuf.dstWidth);

            trxParam.srcX = 0;
            trxParam.srcY = 0;
            trxParam.dstX = 0;
            trxParam.dstY = 0;
            
            std.debug.print("     Source base = 0x{X:0>6}, width = {}, X = {}, Y = {}, Format = {s}\n", .{trxParam.srcBase, trxParam.srcWidth, trxpos.srcX, trxpos.srcY, @tagName(bitbltbuf.srcFmt)});
            std.debug.print("Destination base = 0x{X:0>6}, width = {}, X = {}, Y = {}, Format = {s}\n", .{trxParam.dstBase, trxParam.dstWidth, trxpos.dstX, trxpos.dstY, @tagName(bitbltbuf.dstFmt)});
        },
        Trxdir.Off => {
            std.debug.print("No transmission\n", .{});
        },
    }
}

// Why
var rgb24Pos: i32 = 0;
var rgb24Rem: u32 = 0;

/// Handles GIF->VRAM transfers
fn transmissionGifToVram(data: u64) void {
    std.debug.print("GIF->VRAM write = 0x{X:0>16}\n", .{data});

    const base = trxParam.dstBase;

    const x = trxpos.dstX + trxParam.dstX;
    const y = trxpos.dstY + trxParam.dstY;

    const trxWidth = trxParam.dstWidth;

    // Write data according to pixel format
    switch (bitbltbuf.dstFmt) {
        PixelFormat.Psmct32 => {
            writeVram(u32, PixelFormat.Psmct32, base, trxWidth, x + 0, y, @truncate(u32, data >>  0));
            writeVram(u32, PixelFormat.Psmct32, base, trxWidth, x + 1, y, @truncate(u32, data >> 32));

            trxParam.dstX += 2;
        },
        PixelFormat.Psmct24 => {
            switch (rgb24Pos) {
                0 => {
                    rgb24Rem = @truncate(u32, data >> 48);

                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 0, y, @truncate(u32, data >>  0));
                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 1, y, @truncate(u32, data >> 24));

                    trxParam.dstX += 2;
                },
                1 => {
                    rgb24Rem |= @truncate(u32, data & 0xFF) << 16;

                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 0, y, rgb24Rem);

                    rgb24Rem = @truncate(u32, data >> 56);

                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 1, y, @truncate(u32, data >>  8));
                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 2, y, @truncate(u32, data >> 32));

                    trxParam.dstX += 3;
                },
                2 => {
                    rgb24Rem |= @truncate(u32, data & 0xFFFF) << 8;

                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 0, y, rgb24Rem);

                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 1, y, @truncate(u32, data >> 16));
                    writeVram(u32, PixelFormat.Psmct24, base, trxWidth, x + 2, y, @truncate(u32, data >> 40));

                    trxParam.dstX += 3;
                },
                else => unreachable,
            }

            rgb24Pos = @rem(rgb24Pos + 1, 3);
        },
        PixelFormat.Psmct16 => {
            var i: u23 = 0;
            while (i < 4) : (i += 1) {
                writeVram(u16, PixelFormat.Psmct16, base, trxWidth, x + i, y, @truncate(u16, data >> @truncate(u6, 16 * i)));
            }

            trxParam.dstX += 4;
        },
        PixelFormat.Psmct8 => {
            var i: u23 = 0;
            while (i < 8) : (i += 1) {
                writeVram(u8, PixelFormat.Psmct8, base, trxWidth, x + i, y, @truncate(u8, data >> @truncate(u6, 8 * i)));
            }

            trxParam.dstX += 8;
        },
        PixelFormat.Psmct4hh => {
            var i: u23 = 0;
            while (i < 16) : (i += 1) {
                writeVram(u4, PixelFormat.Psmct4hh, base, trxWidth, x + i, y, @truncate(u4, data >> @truncate(u6, 4 * i)));
            }

            trxParam.dstX += 16;
        },
        PixelFormat.Psmct4hl => {
            var i: u23 = 0;
            while (i < 16) : (i += 1) {
                writeVram(u4, PixelFormat.Psmct4hl, base, trxWidth, x + i, y, @truncate(u4, data >> @truncate(u6, 4 * i)));
            }

            trxParam.dstX += 16;
        },
        else => {
            std.debug.print("Unhandled pixel format: {s}\n", .{@tagName(bitbltbuf.dstFmt)});

            @panic("Unhandled pixel format");
        }
    }

    if (trxParam.dstX >= @as(u23, trxreg.width)) {
        trxParam.dstY += 1;

        if (trxParam.dstY >= @as(u23, trxreg.height)) {
            std.debug.print("Transmission end\n", .{});

            trxdir = Trxdir.Off;
        }

        trxParam.dstX = 0;
    }
}

/// Handles VRAM->VRAM transfers
pub fn transmissionVramToVram() void {
    if (trxpos.dir != 0) @panic("Unhandled transmission direction");

    transLoop: while (true) {
        const srcAddr = trxParam.srcBase + trxParam.srcWidth * (trxpos.srcY + trxParam.srcY) + trxpos.srcX + trxParam.srcX;
        const dstAddr = trxParam.dstBase + trxParam.dstWidth * (trxpos.dstY + trxParam.dstY) + trxpos.dstX + trxParam.dstX;

        vram[dstAddr] = vram[srcAddr];

        trxParam.srcX += 1;
        trxParam.dstX += 1;

        if (trxParam.srcX == @as(u23, trxreg.width)) {
            trxParam.srcY += 1;
            trxParam.dstY += 1;

            if (trxParam.srcY == @as(u23, trxreg.height)) break :transLoop;

            trxParam.srcX = 0;
            trxParam.dstX = 0;
        }
    }

    std.debug.print("Transmission end\n", .{});

    trxdir = Trxdir.Off;
}

/// Steps the GS module
pub fn step(cyclesElapsed: i64) void {
    cyclesToNextLine += cyclesElapsed;

    if (cyclesToNextLine >= cyclesLine) {
        cyclesToNextLine = 0;

        lines += 1;

        timer.stepHblank();
        timerIop.stepHblank();

        csr.hsint = true;

        csr.field = !csr.field;

        //intc.printIntcMask();

        if (lines == 480) {
            intc.sendInterrupt(IntSource.VblankStart);
            intc.sendInterruptIop(IntSourceIop.VblankStart);

            csr.vsint = true;

            renderScreen(@ptrCast(*u8, &vram[framePtr]));

            main.shouldRun = poll();

            setButtonState(getController());
        } else if (lines == 544) {
            lines = 0;

            intc.sendInterrupt(IntSource.VblankEnd);
            intc.sendInterruptIop(IntSourceIop.VblankEnd);
        }
    }
}
