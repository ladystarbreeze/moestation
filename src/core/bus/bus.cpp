/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "bus.hpp"

#include <cstdio>

#include "rdram.hpp"
#include "../intc.hpp"
#include "../ee/dmac/dmac.hpp"
#include "../ee/timer/timer.hpp"
#include "../gif/gif.hpp"
#include "../gs/gs.hpp"
#include "../../common/file.hpp"

/* --- PS2 base addresses --- */

enum class MemoryBase {
    RAM     = 0x00000000,
    EELOAD  = 0x00082000,
    Timer   = 0x10000000,
    IPU     = 0x10002000,
    GIF     = 0x10003000,
    VIF0    = 0x10003800,
    VIF1    = 0x10003C00,
    DMAC    = 0x10008000,
    SIF     = 0x1000F200,
    RDRAM   = 0x1000F430,
    VU0Code = 0x11000000,
    VU0Data = 0x11004000,
    VU1Code = 0x11008000,
    VU1Data = 0x1000C000,
    GS      = 0x12000000,
    IOPRAM  = 0x1C000000,
    IOPIO   = 0x1F800000,
    BIOS    = 0x1FC00000,
};

enum class MemoryBaseIop {
    SIF    = 0x1D000000,
    CDVD   = 0x1F402004,
    DMA0   = 0x1F801080,
    Timer0 = 0x1F801100,
    Timer1 = 0x1F801480,
    DMA1   = 0x1F801500,
    SIO2   = 0x1F808200,
    SPU2   = 0x1F900000,
};

/* --- PS2 memory sizes --- */

enum class MemorySize {
    RAM     = 0x2000000,
    EELOAD  = 0x0020000,
    Timer   = 0x0001840,
    IPU     = 0x0000040,
    GIF     = 0x0000100,
    VIF     = 0x0000180,
    DMAC    = 0x0007000,
    SIF     = 0x0000070,
    RDRAM   = 0x0000020,
    VU0     = 0x0001000,
    VU1     = 0x0004000,
    GS      = 0x0002000,
    IOPRAM  = 0x0200000,
    BIOS    = 0x0400000,
};

enum class MemorySizeIop {
    RAM   = 0x200000,
    CDVD  = 0x000015,
    DMA   = 0x000080,
    Timer = 0x000030,
    SIO2  = 0x000084,
    SPU2  = 0x002800,
};

/* --- PS2 memory --- */

std::vector<u8> ram, iopRam;
std::vector<u8> bios;

/* Returns true if address is in range [base;size] */
bool inRange(u64 addr, u64 base, u64 size) {
    return (addr >= base) && (addr < (base + size));
}

namespace ps2::bus {

void init(const char *biosPath) {
    ram.resize(static_cast<int>(MemorySize::RAM));
    iopRam.resize(static_cast<int>(MemorySizeIop::RAM));

    bios = loadBinary(biosPath);

    std::printf("[Bus       ] Init OK\n");
}

/* Returns a byte from the EE bus */
u8 read8(u32 addr) {
    u8 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        return ram[addr];
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPIO), static_cast<u32>(MemorySize::BIOS))) {
        // Using MemorySize::BIOS works because the IOP I/O has the same size
        std::printf("[Bus:EE    ] Unhandled 8-bit read @ 0x%08X (IOP I/O)\n", addr);

        data = 0;
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        data = bios[addr - static_cast<u32>(MemoryBase::BIOS)];
    } else {
        std::printf("[Bus:EE    ] Unhandled 8-bit read @ 0x%08X\n", addr);

        exit(0);
    }

    return data;
}

/* Returns a halfword from the EE bus */
u16 read16(u32 addr) {
    u16 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        std::memcpy(&data, &ram[addr], sizeof(u16));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        std::memcpy(&data, &bios[addr - static_cast<u32>(MemoryBase::BIOS)], sizeof(u16));
    } else {
        switch (addr) {
            case 0x1A000006:
                //std::printf("[Bus:EE    ] Unhandled 16-bit read @ 0x%08X\n", addr);
                return 1;
            case 0x1000F480:
            case 0x1A000010:
                //std::printf("[Bus:EE    ] Unhandled 16-bit read @ 0x%08X\n", addr);
                return 0;
            default:
                std::printf("[Bus:EE    ] Unhandled 16-bit read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

/* Returns a word from the EE bus */
u32 read32(u32 addr) {
    u32 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        std::memcpy(&data, &ram[addr], sizeof(u32));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::Timer), static_cast<u32>(MemorySize::Timer))) {
        return ps2::ee::timer::read32(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::GIF), static_cast<u32>(MemorySize::GIF))) {
        return ps2::gif::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::DMAC), static_cast<u32>(MemorySize::DMAC))) {
        return ps2::ee::dmac::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::RDRAM), static_cast<u32>(MemorySize::RDRAM))) {
        return rdram::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPRAM), static_cast<u32>(MemorySize::IOPRAM))) {
        std::printf("[Bus:EE    ] Unhandled 32-bit read @ 0x%08X (IOP RAM)\n", addr);
        return 0;
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        std::memcpy(&data, &bios[addr - static_cast<u32>(MemoryBase::BIOS)], sizeof(u32));
    } else {
        switch (addr) {
            case 0x1000F000:
                std::printf("[Bus:EE    ] 32-bit read @ INTC_STAT\n");
                return ps2::intc::readStat();
            case 0x1000F010:
                std::printf("[Bus:EE    ] 32-bit read @ INTC_MASK\n");
                return ps2::intc::readMask();
            case 0x1000F520:
                std::printf("[Bus:EE    ] 32-bit read @ D_ENABLER\n");
                return 0x1201;
            case 0x1000F130:
            case 0x1000F400:
            case 0x1000F410:
                //std::printf("[Bus:EE    ] Unhandled 32-bit read @ 0x%08X\n", addr);
                return 0;
            default:
                std::printf("[Bus:EE    ] Unhandled 32-bit read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

/* Returns a doubleword from the EE bus */
u64 read64(u32 addr) {
    u64 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        std::memcpy(&data, &ram[addr], sizeof(u64));
    } else {
        switch (addr) {
            default:
                std::printf("[Bus:EE    ] Unhandled 64-bit read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

/* Returns a quadword from the EE bus */
u128 read128(u32 addr) {
    u128 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        std::memcpy(&data, &ram[addr], sizeof(u128));
    } else {
        switch (addr) {
            default:
                std::printf("[Bus:EE    ] Unhandled 128-bit read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

/* Writes a byte to the EE bus */
void write8(u32 addr, u8 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        ram[addr] = data;
    } else {
        switch (addr) {
            case 0x1000F180: std::printf("%c", (char)data); break;
            default:
                std::printf("[Bus:EE    ] Unhandled 8-bit write @ 0x%08X = 0x%02X\n", addr, data);

                exit(0);
        }
    }
}

/* Writes a halfword to the EE bus */
void write16(u32 addr, u16 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::IOPIO), static_cast<u32>(MemorySize::BIOS))) {
        // Using MemorySize::BIOS works because the IOP I/O has the same size
        std::printf("[Bus:EE    ] Unhandled 16-bit write @ 0x%08X (IOP I/O) = 0x%04X\n", addr, data);
    } else {
        switch (addr) {
            case 0x1A000000:
            case 0x1A000002:
            case 0x1A000004:
            case 0x1A000006:
            case 0x1A000008:
            case 0x1A000010:
                std::printf("[Bus:EE    ] Unhandled 16-bit write @ 0x%08X = 0x%04X\n", addr, data);
                break;
            default:
                std::printf("[Bus:EE    ] Unhandled 16-bit write @ 0x%08X = 0x%04X\n", addr, data);

                exit(0);
        }
    }
}

/* Writes a word to the EE bus */
void write32(u32 addr, u32 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        memcpy(&ram[addr], &data, sizeof(u32));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::Timer), static_cast<u32>(MemorySize::Timer))) {
        ps2::ee::timer::write32(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::GIF), static_cast<u32>(MemorySize::GIF))) {
        ps2::gif::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::DMAC), static_cast<u32>(MemorySize::DMAC))) {
        return ps2::ee::dmac::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::RDRAM), static_cast<u32>(MemorySize::RDRAM))) {
        return rdram::write(addr, data);
    } else {
        switch (addr) {
            case 0x1000F000:
                std::printf("[Bus:EE    ] 32-bit write @ INTC_STAT = 0x%08X\n", data);
                return ps2::intc::writeStat(data);
            case 0x1000F010:
                std::printf("[Bus:EE    ] 32-bit write @ INTC_MASK = 0x%08X\n", data);
                return ps2::intc::writeMask(data);
            case 0x1000F100:
            case 0x1000F120:
            case 0x1000F140:
            case 0x1000F150:
            case 0x1000F400:
            case 0x1000F410:
            case 0x1000F420:
            case 0x1000F450:
            case 0x1000F460:
            case 0x1000F480:
            case 0x1000F490:
            case 0x1000F500:
                std::printf("[Bus:EE    ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);
                break;
            default:
                std::printf("[Bus:EE    ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    }
}

/* Writes a doubleword to the EE bus */
void write64(u32 addr, u64 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        memcpy(&ram[addr], &data, sizeof(u64));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::GS), static_cast<u32>(MemorySize::GS))) {
        ps2::gs::writePriv64(addr, data);
    } else {
        switch (addr) {
            default:
                std::printf("[Bus:EE    ] Unhandled 64-bit write @ 0x%08X = 0x%016llX\n", addr, data);

                exit(0);
        }
    }
}

/* Writes a word to the EE bus */
void write128(u32 addr, const u128 &data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        memcpy(&ram[addr], &data, sizeof(u128));
    } else {
        switch (addr) {
            case 0x10006000:
                std::printf("[Bus:EE    ] 128-bit write @ GIF_FIFO = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);
                break;
            default:
                std::printf("[Bus:EE    ] Unhandled 128-bit write @ 0x%08X = 0x%016llX%016llX\n", addr, data._u64[1], data._u64[0]);

                exit(0);
        }
    }
}

}
