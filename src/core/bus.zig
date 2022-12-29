//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! core/bus.zig - System bus module
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;
const warn = std.log.warn;

const Allocator = std.mem.Allocator;

const openFile = std.fs.cwd().openFile;
const OpenMode = std.fs.File.OpenMode;

const cpu      = @import("cpu.zig");
const cdvd     = @import("cdvd.zig");
const dmac     = @import("dmac.zig");
const dmacIop  = @import("dmac_iop.zig");
const gif      = @import("gif.zig");
const gs       = @import("gs.zig");
const intc     = @import("intc.zig");
const iop      = @import("iop.zig");
const sif      = @import("sif.zig");
const sio2     = @import("sio2.zig");
const spu2     = @import("spu2.zig");
const timer    = @import("timer.zig");
const timerIop = @import("timer_iop.zig");
const vif1     = @import("vif1.zig");
const vu0      = @import("vu0.zig");

/// Memory base addresses
const MemBase = enum(u32) {
    Ram     = 0x0000_0000,
    EeLoad  = 0x0008_2000,
    Timer   = 0x1000_0000,
    Ipu     = 0x1000_2000,
    Gif     = 0x1000_3000,
    Vif0    = 0x1000_3800,
    Vif1    = 0x1000_3C00,
    Dmac    = 0x1000_8000,
    Sif     = 0x1000_F200,
    Vu0Code = 0x1100_0000,
    Vu0Data = 0x1100_4000,
    Vu1Code = 0x1100_8000,
    Vu1Data = 0x1100_C000,
    Gs      = 0x1200_0000,
    Bios    = 0x1FC0_0000,
};

/// Memory base addresses (IOP)
const MemBaseIop = enum(u32) {
    Sif    = 0x1D00_0000,
    Cdvd   = 0x1F40_2004,
    Dma0   = 0x1F80_1080,
    Timer0 = 0x1F80_1100,
    Timer1 = 0x1F80_1480,
    Dma1   = 0x1F80_1500,
    Sio2   = 0x1F80_8200,
    Spu2   = 0x1F90_0000,
};

/// Memory sizes
const MemSize = enum(u32) {
    Ram    = 0x200_0000,
    EeLoad = 0x002_0000,
    Timer  = 0x000_1840,
    Ipu    = 0x000_0040,
    Gif    = 0x000_0100,
    Vu0    = 0x000_1000,
    Vu1    = 0x000_4000,
    Vif    = 0x000_0180,
    Dmac   = 0x000_7000,
    Sif    = 0x000_0070,
    Gs     = 0x000_2000,
    Bios   = 0x040_0000,
};

/// Memory region sizes (IOP)
const MemSizeIop = enum(u32) {
    Ram   = 0x20_0000,
    Cdvd  = 0x15,
    Dma   = 0x80,
    Timer = 0x30,
    Sio2  = 0x84,
    Spu2  = 0x2800,
};

/// ELF header
const ElfHeader = struct {
    e_ident: [4]u8 = [4]u8 {0, 0, 0, 0},
     e_type: u16 = 0,
    e_entry: u32 = 0,
    e_phoff: u32 = 0,
    e_phnum: u16 = 0,
};

/// Program header
const PHeader = struct {
      p_type: u32 = 0,
    p_offset: u32 = 0,
     p_vaddr: u32 = 0,
     p_paddr: u32 = 0,
    p_filesz: u32 = 0,
     p_memsz: u32 = 0,
     p_flags: u32 = 0,
     p_align: u32 = 0,
};

// Memory arrays
var   bios: []u8 = undefined; // BIOS ROM
var iopRam: []u8 = undefined; // IOP RAM
var  rdram: []u8 = undefined; // RDRAM

// For debug purposes
var elf: []u8 = undefined;

// RDRAM registers
var  mchDrd: u32 = undefined;
var mchRicm: u32 = undefined;

var rdramSdevId: u32 = 0;

/// Initializes the bus module
pub fn init(allocator: Allocator, biosPath: []const u8, elfPath: []const u8) !void {
    info("   [Bus       ] Loading BIOS image {s}...", .{biosPath});

    // Load BIOS file
    const biosFile = try openFile(biosPath, .{.mode = OpenMode.read_only});
    defer biosFile.close();

    bios = try biosFile.reader().readAllAlloc(allocator, @enumToInt(MemSize.Bios));

    info("   [Bus       ] Loading ELF {s}...", .{elfPath});

    // Load ELF file
    const elfFile = try openFile(elfPath, .{.mode = OpenMode.read_only});
    defer elfFile.close();

    elf = try elfFile.reader().readAllAlloc(allocator, 1 << 24);

    iopRam = try allocator.alloc(u8, @enumToInt(MemSizeIop.Ram));
    rdram  = try allocator.alloc(u8, @enumToInt(MemSize.Ram));

    vu0.vuCode = try allocator.alloc(u8, @enumToInt(MemSize.Vu0));
    vu0.vuMem  = try allocator.alloc(u8, @enumToInt(MemSize.Vu0));

    info("   [Bus       ] Successfully loaded BIOS.", .{});
}

/// Deinitializes the bus module
pub fn deinit(allocator: Allocator) void {
    allocator.free(bios);
    allocator.free(iopRam);
    allocator.free(rdram);
    allocator.free(elf);
    allocator.free(vu0.vuCode);
    allocator.free(vu0.vuMem);
}

// Taken from DobieStation. Replace "rom0:OSDSYS" with "cdrom0:[game executable]"
pub fn fastBoot() void {
    const osdsysPath = "rom0:OSDSYS";
    const dvdPath    = "cdrom0:\\\\SLUS_211.13;1"; // Atelier Iris

    var i = @enumToInt(MemBase.EeLoad);
    while (i < (@enumToInt(MemBase.EeLoad) + @enumToInt(MemSize.EeLoad))) : (i += 1) {
        const str = rdram[i..i + osdsysPath.len];

        if (std.mem.eql(u8, osdsysPath, str)) {
            info("   [moestation] OSDSYS path found @ 0x{X:0>8}.", .{i});

            return @memcpy(@ptrCast([*]u8, &rdram[i]), dvdPath, @sizeOf(u8) * dvdPath.len);
        }
    }

    err("  [moestation] Unable to find OSDSYS path.", .{});

    assert(false);
}

/// Loads ELF into RDRAM, returns entry point
pub fn loadElf() u32 {
    var elfHeader = ElfHeader{};

    // Get e_ident
    @memcpy(@ptrCast([*]u8, &elfHeader.e_ident[0]), @ptrCast([*]u8, &elf[0]), 4);

    if (!(elfHeader.e_ident[0] == 0x7F and elfHeader.e_ident[1] == 0x45 and elfHeader.e_ident[2] == 0x4C and elfHeader.e_ident[3] == 0x46)) {
        @panic("Not an ELF file");
    }

    @memcpy(@ptrCast([*]u8, &elfHeader.e_type ), @ptrCast([*]u8, &elf[0x10]), 2);
    @memcpy(@ptrCast([*]u8, &elfHeader.e_entry), @ptrCast([*]u8, &elf[0x18]), 4);
    @memcpy(@ptrCast([*]u8, &elfHeader.e_phoff), @ptrCast([*]u8, &elf[0x1C]), 4);
    @memcpy(@ptrCast([*]u8, &elfHeader.e_phnum), @ptrCast([*]u8, &elf[0x2C]), 2);

    var i: u16 = 0;
    while (i < elfHeader.e_phnum) : (i += 1) {
        var pHeader = PHeader{};

        @memcpy(@ptrCast([*]u8, &pHeader), @ptrCast([*]u8, &elf[elfHeader.e_phoff + 0x20 * i]), 0x20);

        if (pHeader.p_memsz == 0) continue;

        @memcpy(@ptrCast([*]u8, &rdram[pHeader.p_vaddr]), @ptrCast([*]u8, &elf[pHeader.p_offset]), pHeader.p_filesz);
        @memset(@ptrCast([*]u8, &rdram[pHeader.p_vaddr + pHeader.p_filesz]), 0, pHeader.p_memsz - pHeader.p_filesz);
    }

    return elfHeader.e_entry;
}

var tmVal: u128 = 0;

/// Reads data from the system bus
pub fn read(comptime T: type, addr: u32) T {
    assert(T == u8 or T == u16 or T == u32 or T == u64 or T == u128);

    var data: T = undefined;

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &rdram[addr]), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Timer) and addr < (@enumToInt(MemBase.Timer) + @enumToInt(MemSize.Timer))) {
        //err("  [Bus       ] Read ({s}) @ 0x{X:0>8} (Timer).", .{@typeName(T), addr});

        data = @truncate(T, tmVal);

        tmVal += 1;
        tmVal &= 0xFFFF_FFFF;
    } else if (addr >= @enumToInt(MemBase.Ipu) and addr < (@enumToInt(MemBase.Ipu) + @enumToInt(MemSize.Ipu))) {
        if (T != u32) {
            @panic("Unhandled read @ IPU I/O");
        }
        
        warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (IPU).", .{@typeName(T), addr});

        data = 0;
    } else if (addr >= @enumToInt(MemBase.Gif) and addr < (@enumToInt(MemBase.Gif) + @enumToInt(MemSize.Gif))) {
        if (T != u32) {
            @panic("Unhandled read @ GIF I/O");
        }

        data = gif.read(addr);
    } else if (addr >= @enumToInt(MemBase.Vif0) and addr < (@enumToInt(MemBase.Vif0) + @enumToInt(MemSize.Vif))) {
        if (T != u32) {
            @panic("Unhandled read @ VIF0 I/O");
        }
        
        warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (VIF0).", .{@typeName(T), addr});

        data = 0;
    } else if (addr >= @enumToInt(MemBase.Vif1) and addr < (@enumToInt(MemBase.Vif1) + @enumToInt(MemSize.Vif))) {
        if (T != u32) {
            @panic("Unhandled read @ VIF1 I/O");
        }
        
        data = vif1.read(addr);
    } else if (addr >= @enumToInt(MemBase.Dmac) and addr < (@enumToInt(MemBase.Dmac) + @enumToInt(MemSize.Dmac))) {
        if (T != u32) {
            @panic("Unhandled read @ DMAC I/O");
        }

        data = dmac.read(addr);
    } else if (addr >= @enumToInt(MemBase.Sif) and addr < (@enumToInt(MemBase.Sif) + @enumToInt(MemSize.Sif))) {
        if (T != u32) {
            @panic("Unhandled read @ SIF I/O");
        }

        data = sif.read(addr);
    } else if (addr >= @enumToInt(MemBase.Gs) and addr < (@enumToInt(MemBase.Gs) + @enumToInt(MemSize.Gs))) {
        if (T != u32 and T != u64) {
            @panic("Unhandled read @ GS I/O");
        }

        info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (GS).", .{@typeName(T), addr});

        if (T == u32) {
            if (addr == 0x1200_1000) {
                data = ~@as(u32, 0);
            } else {
                data = 0;
            }
        } else {
            if (addr == 0x1200_1000) {
                data = ~@as(u64, 0);
            } else {
                data = 0;
            }
        }

        
    } else if (addr >= 0x1A00_0000 and addr < 0x1FC0_0000) {
        warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (IOP).", .{@typeName(T), addr});

        data = if (addr == 0x1A000006) 1 else 0;
    } else if (addr >= @enumToInt(MemBase.Bios) and addr < (@enumToInt(MemBase.Bios) + @enumToInt(MemSize.Bios))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &bios[addr - @enumToInt(MemBase.Bios)]), @sizeOf(T));
    } else {
        switch (addr) {
            0x1000_F000 => {
                if (T != u32) {
                    @panic("Unhandled read @ INTC_STAT");
                }

                //info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (INTC_STAT).", .{@typeName(T), addr});

                data = intc.getStat();
            },
            0x1000_F010 => {
                if (T != u32) {
                    @panic("Unhandled read @ INTC_MASK");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (INTC_MASK).", .{@typeName(T), addr});

                data = intc.getMask();
            },
            0x1000_F430 => {
                if (T != u32) {
                    @panic("Unhandled read @ MCH_RICM");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (MCH_RICM).", .{@typeName(T), addr});

                data = 0;
            },
            0x1000_F440 => {
                if (T != u32) {
                    @panic("Unhandled read @ MCH_DRD");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (MCH_DRD).", .{@typeName(T), addr});

                const sop = @truncate(u4, mchRicm >> 6);

                if (sop == 0) {
                    const sa = @truncate(u8, mchRicm >> 16);

                    switch (sa) {
                        0x21 => {
                            info("   [RDRAM     ] Register 0x21 (Init).", .{});

                            if (rdramSdevId < 2) {
                                rdramSdevId += 1;

                                data = 0x1F;
                            } else {
                                data = 0;
                            }
                        },
                        0x40 => {
                            info("   [RDRAM     ] Register 0x40 (DevId).", .{});

                            data = mchRicm & 0x1F;
                        },
                        else => {
                            err("  [RDRAM     ] Unhandled RDRAM register 0x{X:0>2}.", .{sa});

                            assert(false);
                        }
                    }
                } else {
                    data = 0;
                }
            },
            0x1000_F520 => {
                if (T != u32) {
                    @panic("Unhandled read @ D_ENABLER");
                }

                info("   [Bus       ] Read ({s}) @ 0x{X:0>8} (D_ENABLER).", .{@typeName(T), addr});

                data = dmac.getEnable();
            },
            0x1000_F130 => data = 0,
            0x1000_F400, 0x1000_F410, 0x1000_F480 => {
                warn("[Bus       ] Read ({s}) @ 0x{X:0>8} (Unknown).", .{@typeName(T), addr});

                data = 0;
            },
            else => {
                err("  [Bus       ] Unhandled read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

                assert(false);
            }
        }
    }

    return data;
}

/// Reads data from the system bus (for DMAC)
pub fn readDmac(addr: u32) u128 {
    var data: u128 = undefined;

    if ((addr & 15) != 0) @panic("Unaligned DMA address!!");

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &rdram[addr]), @sizeOf(u128));
    } else {
        err("  [Bus (DMAC)] Unhandled read @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    return data;
}

/// Reads data from the IOP bus
pub fn readIop(comptime T: type, addr: u32) T {
    var data: T = undefined;

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSizeIop.Ram))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &iopRam[addr]), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBaseIop.Sif) and addr < (@enumToInt(MemBaseIop.Sif) + @enumToInt(MemSize.Sif))) {
        if (T != u32) {
            @panic("Unhandled read @ SIF I/O");
        }

        data = sif.readIop(addr);
    } else if (addr >= @enumToInt(MemBaseIop.Cdvd) and addr < (@enumToInt(MemBaseIop.Cdvd) + @enumToInt(MemSizeIop.Cdvd))) {
        if (T != u8) {
            @panic("Unhandled read @ CDVD");
        }

        data = cdvd.read(addr);
    } else if (addr >= @enumToInt(MemBaseIop.Dma0) and addr < (@enumToInt(MemBaseIop.Dma0) + @enumToInt(MemSizeIop.Dma))) {
        if (T != u32) {
            @panic("Unhandled read @ DMAC I/O");
        }

        data = dmacIop.read(addr);
    } else if (addr >= @enumToInt(MemBaseIop.Timer0) and addr < (@enumToInt(MemBaseIop.Timer0) + @enumToInt(MemSizeIop.Timer))) {
        data = timerIop.read(T, addr);
    } else if (addr >= @enumToInt(MemBaseIop.Timer1) and addr < (@enumToInt(MemBaseIop.Timer1) + @enumToInt(MemSizeIop.Timer))) {
        data = timerIop.read(T, addr);
    } else if (addr >= @enumToInt(MemBaseIop.Dma1) and addr < (@enumToInt(MemBaseIop.Dma1) + @enumToInt(MemSizeIop.Dma))) {
        if (T != u32) {
            @panic("Unhandled read @ DMAC I/O");
        }

        data = dmacIop.read(addr);
    } else if (addr >= @enumToInt(MemBaseIop.Sio2) and addr < (@enumToInt(MemBaseIop.Sio2) + @enumToInt(MemSizeIop.Sio2))) {
        data = sio2.read(T, addr);
    } else if (addr >= @enumToInt(MemBaseIop.Spu2) and addr < (@enumToInt(MemBaseIop.Spu2) + @enumToInt(MemSizeIop.Spu2))) {
        if (T != u16) {
            @panic("Unhandled read @ SPU2 I/O");
        }

        data = spu2.read(addr);
    } else if (addr >= @enumToInt(MemBase.Bios) and addr < (@enumToInt(MemBase.Bios) + @enumToInt(MemSize.Bios))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &bios[addr - @enumToInt(MemBase.Bios)]), @sizeOf(T));
    } else {
        switch (addr) {
            0x1F80_1010 => {
                warn("[Bus (IOP) ] Read ({s}) @ 0x{X:0>8} (Unknown).", .{@typeName(T), addr});

                data = 0;
            },
            0x1F80_1070 => {
                if (T != u32) {
                    @panic("Unhandled read @ I_STAT");
                }

                info("   [Bus (IOP) ] Read ({s}) @ 0x{X:0>8} (I_STAT).", .{@typeName(T), addr});

                data = intc.getStatIop();
            },
            0x1F80_1074 ... 0x1F80_1077 => {
                info("   [Bus (IOP) ] Read ({s}) @ 0x{X:0>8} (I_MASK).", .{@typeName(T), addr});

                data = intc.getMaskIop(T, @truncate(u2, addr));
            },
            0x1F80_1078 => {
                if (T != u32) {
                    @panic("Unhandled read @ I_CTRL");
                }

                //info("   [Bus (IOP) ] Read ({s}) @ 0x{X:0>8} (I_CTRL).", .{@typeName(T), addr});

                data = intc.getCtrl();
            },
            0x1F80_1450 => {
                //warn("[Bus (IOP) ] Read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

                data = 0;
            },
            0x1E00_0000 ... 0x1E00_8000,
            0x1F80_100C,
            0x1F80_1014,
            0x1F80_1400, 0x1F80_1414,
            0x1F80_1578 => {
                warn("[Bus (IOP) ] Read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

                data = 0;
            },
            else => {
                err("  [Bus (IOP) ] Unhandled read ({s}) @ 0x{X:0>8}.", .{@typeName(T), addr});

                assert(false);
            }
        }
    }

    return data;
}



/// Reads data from the system bus (from IOP DMA)
pub fn readDmacIop(addr: u32) u32 {
    var data: u32 = undefined;

    if ((addr & 3) != 0) @panic("Unaligned IOP DMA address!!");

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSizeIop.Ram))) {
        @memcpy(@ptrCast([*]u8, &data), @ptrCast([*]u8, &iopRam[addr]), @sizeOf(u32));
    } else {
        err("  [Bus (DMAC)] Unhandled read @ 0x{X:0>8}.", .{addr});

        assert(false);
    }

    return data;
}

/// Writes data to the system bus
pub fn write(comptime T: type, addr: u32, data: T) void {
    assert(T == u8 or T == u16 or T == u32 or T == u64 or T == u128);

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &rdram[addr]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Timer) and addr < (@enumToInt(MemBase.Timer) + @enumToInt(MemSize.Timer))) {
        if (T != u32 and T != u64) {
            @panic("Unhandled write @ Timer I/O");
        }

        if (T == u32) {
            timer.write(addr, data);
        } else {
            timer.write(addr + 0, @truncate(u32, data));
            timer.write(addr + 4, @truncate(u32, data >> 32));
        }
    } else if (addr >= @enumToInt(MemBase.Ipu) and addr < (@enumToInt(MemBase.Ipu) + @enumToInt(MemSize.Ipu))) {
        if (T != u32) {
            @panic("Unhandled write @ IPU I/O");
        }

        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (IPU) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Gif) and addr < (@enumToInt(MemBase.Gif) + @enumToInt(MemSize.Gif))) {
        if (T != u32) {
            @panic("Unhandled write @ GIF I/O");
        }

        gif.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Vif0) and addr < (@enumToInt(MemBase.Vif0) + @enumToInt(MemSize.Vif))) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VIF0) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Vif1) and addr < (@enumToInt(MemBase.Vif1) + @enumToInt(MemSize.Vif))) {
        if (T != u32) {
            @panic("Unhandled write @ VIF1 I/O");
        }

        vif1.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Dmac) and addr < (@enumToInt(MemBase.Dmac) + @enumToInt(MemSize.Dmac))) {
        if (T != u32) {
            @panic("Unhandled write @ DMAC I/O");
        }

        dmac.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Sif) and addr < (@enumToInt(MemBase.Sif) + @enumToInt(MemSize.Sif))) {
        if (T != u32) {
            @panic("Unhandled write @ SIF I/O");
        }

        sif.write(addr, data);
    } else if (addr >= @enumToInt(MemBase.Vu0Code) and addr < (@enumToInt(MemBase.Vu0Code) + @enumToInt(MemSize.Vu0))) {
        //info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (VU0 Code) = 0x{X}.", .{@typeName(T), addr, data});

        @memcpy(@ptrCast([*]u8, &vu0.vuCode[addr - @enumToInt(MemBase.Vu0Code)]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Vu0Data) and addr < (@enumToInt(MemBase.Vu0Data) + @enumToInt(MemSize.Vu0))) {
        //info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (VU0 Data) = 0x{X}.", .{@typeName(T), addr, data});

        @memcpy(@ptrCast([*]u8, &vu0.vuMem[addr - @enumToInt(MemBase.Vu0Data)]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBase.Vu1Code) and addr < (@enumToInt(MemBase.Vu1Code) + @enumToInt(MemSize.Vu1))) {
        //warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VU1 Code) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Vu1Data) and addr < (@enumToInt(MemBase.Vu1Data) + @enumToInt(MemSize.Vu1))) {
        //warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VU1 Data) = 0x{X}.", .{@typeName(T), addr, data});
    } else if (addr >= @enumToInt(MemBase.Gs) and addr < (@enumToInt(MemBase.Gs) + @enumToInt(MemSize.Gs))) {
        if (T != u32 and T != u64) {
            @panic("Unhandled write @ GS I/O");
        }

        gs.writePriv(addr, @as(u64, data));
    } else if (addr >= 0x1A00_0000 and addr < 0x1FC0_0000) {
        warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (IOP) = 0x{X}.", .{@typeName(T), addr, data});
    } else {
        switch (addr) {
            0x1000_4000 => {
                if (T != u128) {
                    @panic("Unhandled write @ VIF0 FIFO");
                }

                warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (VIF0 FIFO) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1000_5000 => {
                if (T != u128) {
                    @panic("Unhandled write @ VIF1 FIFO");
                }

                vif1.writeFifo(data);
            },
            0x1000_6000 => {
                if (T != u128) {
                    @panic("Unhandled write @ GIF FIFO");
                }

                gif.writeFifo(data);
            },
            0x1000_7010 => {
                if (T != u128) {
                    @panic("Unhandled write @ IPU In FIFO");
                }

                warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (IPU In FIFO) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1000_F000 => {
                if (T != u32) {
                    @panic("Unhandled write @ INTC_STAT");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (INTC_STAT) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setStat(data);
            },
            0x1000_F010 => {
                if (T != u32) {
                    @panic("Unhandled write @ INTC_MASK");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (INTC_MASK) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setMask(data);
            },
            0x1000_F180 => {
                if (T != u8) {
                    @panic("Unhandled write @ KPUTCHAR");
                }

                // info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (KPUTCHAR) = 0x{X}.", .{@typeName(T), addr, data});

                if (data != 0) {
                    const stdOut = std.io.getStdOut().writer();

                    stdOut.print("{c}", .{data}) catch unreachable;
                }
            },
            0x1000_F430 => {
                if (T != u32) {
                    @panic("Unhandled write @ MCH_RICM");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (MCH_RICM) = 0x{X}.", .{@typeName(T), addr, data});

                const  sa = @truncate(u8, data >> 16);
                const sbc = @truncate(u4, data >>  6);

                if ((sa == 0x21) and (sbc == 1) and ((mchDrd & (1 << 7)) == 0)) {
                    rdramSdevId = 0;
                }

                mchRicm = data & ~@as(u32, 0x80000000);
            },
            0x1000_F440 => {
                if (T != u32) {
                    @panic("Unhandled write @ MCH_DRD");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (MCH_DRD) = 0x{X}.", .{@typeName(T), addr, data});

                mchDrd = data;
            },
            0x1000_F590 => {
                if (T != u32) {
                    @panic("Unhandled write @ D_ENABLEW");
                }

                info("   [Bus       ] Write ({s}) @ 0x{X:0>8} (D_ENABLEW) = 0x{X}.", .{@typeName(T), addr, data});

                dmac.setEnable(data);
            },
            0x1000_F100, 0x1000_F120, 0x1000_F140, 0x1000_F150,
            0x1000_F400, 0x1000_F410, 0x1000_F420, 0x1000_F450, 0x1000_F460, 0x1000_F480, 0x1000_F490,
            0x1000_F500, 0x1000_F510 => warn("[Bus       ] Write ({s}) @ 0x{X:0>8} (Unknown) = 0x{X}.", .{@typeName(T), addr, data}),
            else => {
                err("  [Bus       ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X}.", .{@typeName(T), addr, data});

                cpu.dumpRegs();

                //dumpRam();

                assert(false);
            }
        }
    }
}

/// Reads data from the system bus (for DMAC)
pub fn writeDmac(addr: u32, data: u128) void {
    //info("   [Bus (DMAC)] [0x{X:0>8}] = 0x{X:0>32}", .{addr, data});
    if ((addr & 15) != 0) @panic("Unaligned DMA address!!");

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSize.Ram))) {
        @memcpy(@ptrCast([*]u8, &rdram[addr]), @ptrCast([*]const u8, &data), @sizeOf(u128));
    } else {
        err("  [Bus (DMAC)] Unhandled write @ 0x{X:0>8} = 0x{X:0>32}.", .{addr, data});

        assert(false);
    }
}

/// Writes data to the IOP bus
pub fn writeIop(comptime T: type, addr: u32, data: T) void {
    if ((addr >= 0x01B354 and addr < 0x01B35C) or (addr >= 0x01B154 and addr < 0x01B15C) or (addr >= 0x01B364 and addr < 0x01B36C) or (addr >= 0x05A3D0 and addr < 0x05A400)) {
    //if (addr == 0x05B1FC) {
        //info("   [Bus       ] Write @ 0x{X:0>8} = 0x{X}.", .{addr, data});
        //info("   [Bus       ] PC = 0x{X:0>8}", .{iop.getPc()});
    }

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSizeIop.Ram))) {
        @memcpy(@ptrCast([*]u8, &iopRam[addr]), @ptrCast([*]const u8, &data), @sizeOf(T));
    } else if (addr >= @enumToInt(MemBaseIop.Sif) and addr < (@enumToInt(MemBaseIop.Sif) + @enumToInt(MemSize.Sif))) {
        if (T != u32) {
            @panic("Unhandled write @ SIF I/O");
        }

        sif.writeIop(addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Cdvd) and addr < (@enumToInt(MemBaseIop.Cdvd) + @enumToInt(MemSizeIop.Cdvd))) {
        if (T != u8) {
            @panic("Unhandled write @ CDVD");
        }

        cdvd.write(addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Dma0) and addr < (@enumToInt(MemBaseIop.Dma0) + @enumToInt(MemSizeIop.Dma))) {
        dmacIop.write(T, addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Timer0) and addr < (@enumToInt(MemBaseIop.Timer0) + @enumToInt(MemSizeIop.Timer))) {
        timerIop.write(T, addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Timer1) and addr < (@enumToInt(MemBaseIop.Timer1) + @enumToInt(MemSizeIop.Timer))) {
        timerIop.write(T, addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Dma1) and addr < (@enumToInt(MemBaseIop.Dma1) + @enumToInt(MemSizeIop.Dma))) {
        dmacIop.write(T, addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Sio2) and addr < (@enumToInt(MemBaseIop.Sio2) + @enumToInt(MemSizeIop.Sio2))) {
        sio2.write(T, addr, data);
    } else if (addr >= @enumToInt(MemBaseIop.Spu2) and addr < (@enumToInt(MemBaseIop.Spu2) + @enumToInt(MemSizeIop.Spu2))) {
        if (T != u16) {
            @panic("Unhandled write @ SPU2 I/O");
        }

        spu2.write(addr, data);
    } else {
        switch (addr) {
            0x1F80_1070 ... 0x1F80_1073 => {
                info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (I_STAT) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setStatIop(T, data, @truncate(u2, addr));
            },
            0x1F80_1074 ... 0x1F80_1077 => {
                info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (I_MASK) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setMaskIop(T, data, @truncate(u2, addr));
            },
            0x1F80_1078 => {
                //info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (I_CTRL) = 0x{X}.", .{@typeName(T), addr, data});

                intc.setCtrl(data);
            },
            0x1FA0_0000 => {
                info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (POST) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1FFE_0130 => {
                info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (Cache Control) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1FFE_0140 => {
                info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (Scratchpad End) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1FFE_0144 => {
                info("   [Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (Scratchpad Start) = 0x{X}.", .{@typeName(T), addr, data});
            },
            0x1F80_1000 ... 0x1F80_1020,
            0x1F80_1060,
            0x1F80_1400 ... 0x1F80_1420,
            0x1F80_1450,
            0x1F80_15F0,
            0x1F80_2070 => {
                warn("[Bus (IOP) ] Write ({s}) @ 0x{X:0>8} (Unknown) = 0x{X}.", .{@typeName(T), addr, data});
            },
            else => {
                err("  [Bus (IOP) ] Unhandled write ({s}) @ 0x{X:0>8} = 0x{X}.", .{@typeName(T), addr, data});

                assert(false);
            }
        }
    }
}

/// Writes data to the IOP bus (from IOP DMA)
pub fn writeIopDmac(addr: u24, data: u32) void {
    //info("   [Bus (DMAC)] [0x{X:0>6}] = 0x{X:0>8}", .{addr, data});
    if ((addr & 3) != 0) @panic("Unaligned IOP DMA address!!");

    if (addr == 0x05B1FC) {
        //info("   [Bus (DMAC)] Write @ 0x{X:0>8} = 0x{X}", .{addr, data});
        //err("  [Bus       ] PC = 0x{X:0>8}", .{iop.getPc()});
    }

    if (addr >= @enumToInt(MemBase.Ram) and addr < (@enumToInt(MemBase.Ram) + @enumToInt(MemSizeIop.Ram))) {
        @memcpy(@ptrCast([*]u8, &iopRam[addr]), @ptrCast([*]const u8, &data), @sizeOf(u32));
    } else {
        err("  [Bus (DMAC)] Unhandled write @ 0x{X:0>8} = 0x{X:0>8}.", .{addr, data});

        assert(false);
    }
}

/// Dumps RDRAM and IOP RAM images
pub fn dumpRam() void {
    info("   [Bus       ] Dumping RAM...", .{});

    // Open RAM file
    const ramFile = openFile("moeFiles/ram.bin", .{.mode = OpenMode.write_only}) catch {
        err("  [moestation] Unable to open file.", .{});

        return;
    };

    // Open IOP RAM file
    const ramIopFile = openFile("moeFiles/ram_iop.bin", .{.mode = OpenMode.write_only}) catch {
        err("  [moestation] Unable to open file.", .{});

        return;
    };

    defer ramIopFile.close();

    ramFile.writer().writeAll(rdram) catch {
        err("  [moestation] Unable to write to file.", .{});
    };

    ramIopFile.writer().writeAll(iopRam) catch {
        err("  [moestation] Unable to write to file.", .{});
    };
}
