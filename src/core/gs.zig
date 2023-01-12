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

const intc = @import("intc.zig");

const IntSource = intc.IntSource;
const IntSourceIop = intc.IntSourceIop;

const timer = @import("timer.zig");
const timerIop = @import("timer_iop.zig");

const main = @import("../main.zig");

const poll = main.poll;
const renderScreen = main.renderScreen;

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

    /// Returns size of pixel format in bits
    pub fn getPixelSize(fmt: PixelFormat) u23 {
        return switch (fmt) {
            PixelFormat.Psmct32, PixelFormat.Psmz32   => 32,
            PixelFormat.Psmct24, PixelFormat.Psmz24   => 24,
            PixelFormat.Psmct16, PixelFormat.Psmct16s => 16,
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

/// Vertex
const Vertex = struct {
    // Coordinates
    x: i16 = undefined,
    y: i16 = undefined,
    z: u32 = undefined,

    // Colors
    r: u8 = undefined,
    g: u8 = undefined,
    b: u8 = undefined,
    a: u8 = undefined,
};

/// Depth test
const ZTest = enum(u2) {
    Never,
    Always,
    GEqual,
    Greater,
};

/// --- GS internal registers

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
    q: u32 = 0,

    /// Sets RGBAQ
    pub fn set(self: *Rgbaq, data: u64) void {
        self.r = @truncate(u8 , data);
        self.g = @truncate(u8 , data >>  8);
        self.b = @truncate(u8 , data >> 16);
        self.a = @truncate(u8 , data >> 24);
        self.q = @truncate(u32, data >> 32);
    }
};

/// Scissor setting
const Scissor = struct {
    scax0: i16 = 0,
    scax1: i16 = 0,
    scay0: i16 = 0,
    scay1: i16 = 0,

    /// Sets SCISSOR
    pub fn set(self: *Scissor, data: u64) void {
        self.scax0 = @as(i16, @bitCast(i11, @truncate(u11, data >>  0)));
        self.scax1 = @as(i16, @bitCast(i11, @truncate(u11, data >> 16)));
        self.scay0 = @as(i16, @bitCast(i11, @truncate(u11, data >> 32)));
        self.scay1 = @as(i16, @bitCast(i11, @truncate(u11, data >> 48)));
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
    ofx: i16 = 0,
    ofy: i16 = 0,

    /// Sets XYOFFSET
    pub fn set(self: *Xyoffset, data: u64) void {
        self.ofx = @bitCast(i16, @truncate(u16, data));
        self.ofy = @bitCast(i16, @truncate(u16, data >> 32));
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

const VertexQueue = LinearFifo(Vertex, LinearFifoBufferType{.Static = 16});

/// Vertex queue
var vtxQueue = VertexQueue.init();

var vtxCount: i32 = 0;

// GS registers
var gsRegs: [0x63]u64 = undefined;

var       prim: Prim = Prim{};
var     prmode: Prim = Prim{};
var prmodecont: bool = false;

var rgbaq: Rgbaq = Rgbaq{};

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

/// Clears vertex queue, sets primitive vertex number
fn clearVtxQueue(n: i32) void {
    vtxQueue = VertexQueue.init();
    vtxCount = n;
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

            switch (prim.prim) {
                Primitive.Line     => clearVtxQueue(2),
                Primitive.Triangle => clearVtxQueue(3),
                Primitive.Sprite   => clearVtxQueue(2),
                else => {
                    std.debug.print("Unhandled primitive: {s}\n", .{@tagName(prim.prim)});

                    @panic("Unhandled primitive");
                }
            }
        },
        @enumToInt(GsReg.Rgbaq     ) => rgbaq.set(data),
        @enumToInt(GsReg.Xyzf2     ),
        @enumToInt(GsReg.Xyz2      ), => {
            var vtx = Vertex{};

            vtx.x = @intCast(i16, @truncate(u16, data));
            vtx.y = @intCast(i16, @truncate(u16, data >> 16));

            if (addr == @enumToInt(GsReg.Xyzf2)) {
                vtx.z = @as(u32, @truncate(u24, data >> 32)) << 8;
            } else {
                vtx.z = @as(u32, @truncate(u32, data >> 32));
            }

            // TODO: write fog value

            vtx.r = rgbaq.r;
            vtx.g = rgbaq.g;
            vtx.b = rgbaq.b;
            vtx.a = rgbaq.a;

            vtxQueue.writeItem(vtx) catch {
                err("  [GS        ] Vertex queue is full.", .{});
                
                assert(false);
            };

            vtxCount -= 1;

            if (vtxCount == 0) {
                switch (prim.prim) {
                    Primitive.Triangle => drawTriangle(),
                    Primitive.Sprite   => drawSprite(),
                    else => {
                        std.debug.print("Unsupported primitive: {s}\n", .{@tagName(prim.prim)});
                    }
                }

                switch (prim.prim) {
                    Primitive.Line     => clearVtxQueue(2),
                    Primitive.Triangle => clearVtxQueue(3),
                    Primitive.Sprite   => clearVtxQueue(2),
                    else => {
                        std.debug.print("Unhandled primitive: {s}\n", .{@tagName(prim.prim)});

                        @panic("Unhandled primitive");
                    }
                }
            }
        },
        @enumToInt(GsReg.PrMode    ) => prmode.set(data),
        @enumToInt(GsReg.XyOffset1 ) => xyoffset[0].set(data),
        @enumToInt(GsReg.XyOffset2 ) => xyoffset[1].set(data),
        @enumToInt(GsReg.PrModeCont) => prmodecont = (data & 1) != 0,
        @enumToInt(GsReg.Scissor1  ) => scissor[0].set(data),
        @enumToInt(GsReg.Scissor2  ) => scissor[1].set(data),
        @enumToInt(GsReg.Test1     ) => test_[0].set(data),
        @enumToInt(GsReg.Test2     ) => test_[1].set(data),
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
        @enumToInt(GsReg.Finish) => csr.finish = true,
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
            var rgbaq_: u64 = 0;

            // TODO: add Q!
            rgbaq_ |= @as(u64, @truncate(u8, data));
            rgbaq_ |= @as(u64, @truncate(u8, data >> 32)) <<  8;
            rgbaq_ |= @as(u64, @truncate(u8, data >> 64)) << 16;
            rgbaq_ |= @as(u64, @truncate(u8, data >> 96)) << 24;

            write(@enumToInt(GsReg.Rgbaq), rgbaq_);
        },
        @enumToInt(GsReg.St) => {
            write(@enumToInt(GsReg.St), @truncate(u64, data));
        },
        @enumToInt(GsReg.Uv) => {
            const uv = @truncate(u64, ((data >> 16) & 0x3FFF_0000) | (data & 0x3FFF));

            write(@enumToInt(GsReg.Uv), uv);
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
            xyz |= @as(u64, @truncate(u24, data >>  64)) << 32;

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
        0x6, 0x8, 0xC => write(addr, @truncate(u64, data)),
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
        @enumToInt(PrivReg.Pmode   ),
        @enumToInt(PrivReg.Smode1  ),
        @enumToInt(PrivReg.Smode2  ),
        @enumToInt(PrivReg.Srfsh   ),
        @enumToInt(PrivReg.Synch1  ),
        @enumToInt(PrivReg.Synch2  ),
        @enumToInt(PrivReg.Syncv   ),
        @enumToInt(PrivReg.Dispfb1 ),
        @enumToInt(PrivReg.Display1),
        @enumToInt(PrivReg.Dispfb2 ),
        @enumToInt(PrivReg.Display2),
        @enumToInt(PrivReg.Bgcolor ) => {},
        else => {
            err("  [GS        ] Unhandled write @ 0x{X:0>8} = 0x{X:0>16} ({s}).", .{addr, data, @tagName(@intToEnum(PrivReg, addr))});

            assert(false);
        }
    }

    info("   [GS        ] Write @ 0x{X:0>8} = 0x{X:0>16} ({s}).", .{addr, data, @tagName(@intToEnum(PrivReg, addr))});
}

/// Computes edge function
fn edgeFunction(a: Vertex, b: Vertex, c: Vertex) i32 {
    return (@as(i32, b.x) - @as(i32, a.x)) * (@as(i32, c.y) - @as(i32, a.y)) - (@as(i32, b.y) - @as(i32, a.y)) * (@as(i32, c.x) - @as(i32, a.x));
}

/// Performs a depth test
fn depthTest(x: i16, y: i16, depth: u32) bool {
    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    if (!test_[ctxt].zte) return true;

    const zAddr = @as(u23, zbuf[ctxt].zbp) * 2048;

    const oldDepth = vram[zAddr + 1024 * @as(u23, @bitCast(u16, y)) + @as(u23, @bitCast(u16, x))];

    switch (test_[ctxt].ztst) {
        ZTest.Never   => return false,
        ZTest.Always  => {},
        ZTest.GEqual  => if (depth <  oldDepth) return false,
        ZTest.Greater => if (depth <= oldDepth) return false,
    }

    if (!zbuf[ctxt].zmsk) vram[zAddr + 1024 * @as(u23, @bitCast(u16, y)) + @as(u23, @bitCast(u16, x))] = depth;

    return true;
}

/// Draws a sprite
fn drawSprite() void {
    std.debug.print("Drawing sprite...\n", .{});

    var a = vtxQueue.readItem().?;
    var b = vtxQueue.readItem().?;

    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    // Offset coordinates
    a.x -= xyoffset[ctxt].ofx;
    b.x -= xyoffset[ctxt].ofx;
    a.y -= xyoffset[ctxt].ofy;
    b.y -= xyoffset[ctxt].ofy;
    
    a.x >>= 4;
    a.y >>= 4;
    b.x >>= 4;
    b.y >>= 4;

    std.debug.print("a = [{};{}], b = [{};{}]\n", .{a.x, a.y, b.x, b.y});

    var a_ = Vertex{};
    var b_ = Vertex{};

    // Sort vertices from left to right
    if (a.x < b.x) {
        a_ = a;
        b_ = b;
    } else {
        a_ = b;
        b_ = a;
    }

    // Swap Y coordinates to draw from top-left to bottom-right
    if (a_.y > b_.y) {
        const temp = b_.y;

        b_.y = a_.y;
        a_.y = temp;
    }

    const fbAddr = @as(u23, frame[ctxt].fbp) * 2048;

    std.debug.print("Frame buffer address = 0x{X:0>6}, OFX = {}, OFY = {}\n", .{fbAddr, xyoffset[ctxt].ofx >> 4, xyoffset[ctxt].ofy >> 4});
    std.debug.print("SCAX0 = {}, SCAX1 = {}, SCAY0 = {}, SCAY1 = {}\n", .{scissor[ctxt].scax0, scissor[ctxt].scax1, scissor[ctxt].scay0, scissor[ctxt].scay1});

    const xMax = b_.x - a_.x;
    const yMax = b_.y - a_.y;

    var y = a_.y;
    while (y <= yMax) : (y += 1) {
        var x = a_.x;
        while (x <= xMax) : (x += 1) {
            if (x >= scissor[ctxt].scax0 and x <= scissor[ctxt].scax1 and y >= scissor[ctxt].scay0 and y <= scissor[ctxt].scay1) {
                if (!depthTest(x, y, a.z)) continue;

                const color = (@as(u32, a.a) << 24) | (@as(u32, a.b) << 16) | (@as(u32, a.g) << 8) | @as(u32, a.r);

                vram[fbAddr + 1024 * @as(u23, @bitCast(u16, y)) + @as(u23, @bitCast(u16, x))] = color;
            }
        }
    }
}

/// Draws a triangle
fn drawTriangle() void {
    std.debug.print("Drawing triangle...\n", .{});

    var a = vtxQueue.readItem().?;
    var b = vtxQueue.readItem().?;
    var c = vtxQueue.readItem().?;

    const ctxt = if (prmodecont) @bitCast(u1, prim.ctxt) else @bitCast(u1, prmode.ctxt);

    // Offset coordinates
    a.x -= xyoffset[ctxt].ofx;
    b.x -= xyoffset[ctxt].ofx;
    c.x -= xyoffset[ctxt].ofx;
    a.y -= xyoffset[ctxt].ofy;
    b.y -= xyoffset[ctxt].ofy;
    c.y -= xyoffset[ctxt].ofy;
    
    a.x >>= 4;
    a.y >>= 4;
    b.x >>= 4;
    b.y >>= 4;
    c.x >>= 4;
    c.y >>= 4;

    std.debug.print("a = [{};{}], b = [{};{}], c = [{};{}]\n", .{a.x, a.y, b.x, b.y, c.x, c.y});

    var p = Vertex{};
    var b_= Vertex{};
    var c_= Vertex{};

    if ((edgeFunction(a, b, c)) < 0) {
        b_ = c;
        c_ = b;
    } else {
        b_ = b;
        c_ = c;
    }

    const fbAddr = @as(u23, frame[ctxt].fbp) * 2048;
    //const fbWidth = @as(u23, frame[ctxt].fbw) * 64;

    std.debug.print("Frame buffer address = 0x{X:0>6}, OFX = {}, OFY = {}\n", .{fbAddr, xyoffset[ctxt].ofx >> 4, xyoffset[ctxt].ofy >> 4});
    std.debug.print("SCAX0 = {}, SCAX1 = {}, SCAY0 = {}, SCAY1 = {}\n", .{scissor[ctxt].scax0, scissor[ctxt].scax1, scissor[ctxt].scay0, scissor[ctxt].scay1});

    p.y = scissor[ctxt].scay0;
    while (p.y <= scissor[ctxt].scay1) : (p.y += 1) {
        p.x = scissor[ctxt].scax0;
        while (p.x <= scissor[ctxt].scax1) : (p.x += 1) {
            const w0 = edgeFunction(b_, c_, p);
            const w1 = edgeFunction(c_, a , p);
            const w2 = edgeFunction(a , b_, p);

            //std.debug.print("w0 = {}, w1 = {}, w2 = {}\n", .{w0, w1, w2});

            if (w0 >= 0 and w1 >= 0 and w2 >= 0) {
                if (!depthTest(p.x, p.y, a.z)) continue;
                
                const color = (@as(u32, a.a) << 24) | (@as(u32, a.b) << 16) | (@as(u32, a.g) << 8) | @as(u32, a.r);

                vram[fbAddr + 1024 * @as(u23, @bitCast(u16, p.y)) + @as(u23, @bitCast(u16, p.x))] = color;

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

            const srcSize = PixelFormat.getPixelSize(bitbltbuf.dstFmt);
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

/// Handles GIF->VRAM transfers
fn transmissionGifToVram(data: u64) void {
    std.debug.print("GIF->VRAM write = 0x{X:0>16}\n", .{data});

    var addr = trxParam.dstBase + 1024 * (trxpos.dstY + trxParam.dstY);

    // Write data according to pixel format
    switch (bitbltbuf.dstFmt) {
        PixelFormat.Psmct32 => {
            addr += trxpos.dstX + trxParam.dstX;

            vram[addr + 0] = @truncate(u32, data);
            vram[addr + 1] = @truncate(u32, data >> 32);

            trxParam.dstX += 2;
        },
        PixelFormat.Psmct16 => {
            addr += (trxpos.dstX + trxParam.dstX) / 2;

            vram[addr + 0] = @truncate(u32, data);
            vram[addr + 1] = @truncate(u32, data >> 32);

            trxParam.dstX += 4;
        },
        PixelFormat.Psmct4hh => {
            addr += trxpos.dstX + trxParam.dstX;

            var i: u23 = 0;
            while (i < 16) : (i += 1) {
                vram[addr + i] = (vram[addr + i] & 0xFFF_FFFF) | (@as(u32, @truncate(u4, data >> @truncate(u6, 4 * i))) << 28);
            }

            trxParam.dstX += 16;
        },
        PixelFormat.Psmct4hl => {
            addr += trxpos.dstX + trxParam.dstX;

            var i: u23 = 0;
            while (i < 16) : (i += 1) {
                vram[addr + i] = (vram[addr + i] & 0xF0FF_FFFF) | (@as(u32, @truncate(u4, data >> @truncate(u6, 4 * i))) << 24);
            }

            trxParam.dstX += 16;
        },
        else => {
            std.debug.print("Unhandled pixel format: {s}\n", .{@tagName(bitbltbuf.dstFmt)});

            @panic("Unhandled pixel format");
        }
    }

    if (trxParam.dstX == @as(u23, trxreg.width)) {
        trxParam.dstY += 1;

        if (trxParam.dstY == @as(u23, trxreg.height)) {
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
        const srcAddr = trxParam.srcBase + 1024 * (trxpos.srcY + trxParam.srcY) + trxpos.srcX + trxParam.srcX;
        const dstAddr = trxParam.dstBase + 1024 * (trxpos.dstY + trxParam.dstY) + trxpos.dstX + trxParam.dstX;

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

            renderScreen(@ptrCast(*u8, vram));

            main.shouldRun = poll();
        } else if (lines == 544) {
            lines = 0;

            intc.sendInterrupt(IntSource.VblankEnd);
            intc.sendInterruptIop(IntSourceIop.VblankEnd);
        }
    }
}
