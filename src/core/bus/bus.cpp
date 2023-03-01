/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "bus.hpp"

#include <cstdio>

#include "rdram.hpp"
#include "../intc.hpp"
#include "../sif.hpp"
#include "../ee/dmac/dmac.hpp"
#include "../ee/ipu/ipu.hpp"
#include "../ee/timer/timer.hpp"
#include "../gif/gif.hpp"
#include "../gs/gs.hpp"
#include "../iop/timer/timer.hpp"
#include "../../common/file.hpp"

namespace ps2::bus {

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
    VU1Data = 0x1100C000,
    GS      = 0x12000000,
    IOPRAM  = 0x1C000000,
    IOPIO   = 0x1F800000,
    BIOS    = 0x1FC00000,
};

enum class MemoryBaseIOP {
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

enum class MemorySizeIOP {
    RAM   = 0x200000,
    CDVD  = 0x000015,
    DMA   = 0x000080,
    Timer = 0x000030,
    SIO2  = 0x000084,
    SPU2  = 0x002800,
};

/* --- PS2 memory --- */

std::vector<u8> ram, iopRAM;
std::vector<u8> bios;

/* IOP scratchpad */
u8  iopSPRAM[0x400];
u32 spramStart = -1, spramEnd = -1;

/* Vector Interfaces */
VectorInterface *vif[2];

/* Returns true if address is in range [base;size] */
bool inRange(u64 addr, u64 base, u64 size) {
    return (addr >= base) && (addr < (base + size));
}

void init(const char *biosPath, VectorInterface *vif0, VectorInterface *vif1) {
    ram.resize(static_cast<int>(MemorySize::RAM));
    iopRAM.resize(static_cast<int>(MemorySizeIOP::RAM));

    bios = loadBinary(biosPath);

    vif[0] = vif0;
    vif[1] = vif1;

    std::printf("[Bus       ] Init OK\n");
}

void setPathEELOAD(const char *path) {
    static const char osdsysPath[] = "rom0:OSDSYS";

    for (auto i = static_cast<int>(MemoryBase::EELOAD); i < (static_cast<int>(MemoryBase::EELOAD) + static_cast<int>(MemorySize::EELOAD)); i++) {
        if (std::strncmp((char *)&ram[i], osdsysPath, sizeof(osdsysPath)) == 0) {
            std::printf("[moestation] OSDSYS path found @ 0x%08X\n", i);

            std::memcpy((char *)&ram[i], path, 23);

            return;
        }
    }

    std::printf("[moestation] Unable to find OSDSYS path\n");

    exit(0);
}

/* Returns a byte from the EE bus */
u8 read8(u32 addr) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        return ram[addr];
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPIO), static_cast<u32>(MemorySize::BIOS))) {
        // Using MemorySize::BIOS works because the IOP I/O has the same size
        std::printf("[Bus:EE    ] Unhandled 8-bit read @ 0x%08X (IOP I/O)\n", addr);
        return 0;
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPRAM), static_cast<u32>(MemorySize::IOPRAM))) {
        return iopRAM[addr - static_cast<u32>(MemoryBase::IOPRAM)];
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        return bios[addr - static_cast<u32>(MemoryBase::BIOS)];
    } else {
        std::printf("[Bus:EE    ] Unhandled 8-bit read @ 0x%08X\n", addr);

        exit(0);
    }
}

/* Returns a halfword from the EE bus */
u16 read16(u32 addr) {
    u16 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        std::memcpy(&data, &ram[addr], sizeof(u16));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPIO), static_cast<u32>(MemorySize::BIOS))) {
        std::printf("[Bus:EE    ] Unhandled 16-bit read @ 0x%08X (IOP I/O)\n", addr);
        return 0;
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
        return ee::timer::read32(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IPU), static_cast<u32>(MemorySize::IPU))) {
        return ee::ipu::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::GIF), static_cast<u32>(MemorySize::GIF))) {
        return gif::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::DMAC), static_cast<u32>(MemorySize::DMAC))) {
        return ee::dmac::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::SIF), static_cast<u32>(MemorySize::SIF))) {
        return sif::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::RDRAM), static_cast<u32>(MemorySize::RDRAM))) {
        return rdram::read(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPRAM), static_cast<u32>(MemorySize::IOPRAM))) {
        std::memcpy(&data, &iopRAM[addr - static_cast<u32>(MemoryBase::IOPRAM)], sizeof(u32));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        std::memcpy(&data, &bios[addr - static_cast<u32>(MemoryBase::BIOS)], sizeof(u32));
    } else {
        switch (addr) {
            case 0x1000F000:
                //std::printf("[Bus:EE    ] 32-bit read @ INTC_STAT\n");
                return intc::readStat();
            case 0x1000F010:
                std::printf("[Bus:EE    ] 32-bit read @ INTC_MASK\n");
                return intc::readMask();
            case 0x1000F520:
                std::printf("[Bus:EE    ] 32-bit read @ D_ENABLER\n");
                return ee::dmac::readEnable();
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

/* Returns a byte from the IOP bus */
u8 readIOP8(u32 addr) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySizeIOP::RAM))) {
        return iopRAM[addr];
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::CDVD), static_cast<u32>(MemorySizeIOP::CDVD))) {
        std::printf("[Bus:IOP   ] Unhandled 8-bit read @ 0x%08X (CDVD)\n", addr);
        return 0;
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        return bios[addr - static_cast<u32>(MemoryBase::BIOS)];
    } else if ((addr >= spramStart) && (addr < spramEnd)) {
        return iopSPRAM[addr - spramStart];
    } else {
        switch (addr) {
            default:
                std::printf("[Bus:IOP   ] Unhandled 8-bit read @ 0x%08X\n", addr);

                exit(0);
        }
    }
}

/* Returns a halfword from the IOP bus */
u16 readIOP16(u32 addr) {
    u16 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySizeIOP::RAM))) {
        std::memcpy(&data, &iopRAM[addr], sizeof(u16));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        std::memcpy(&data, &bios[addr - static_cast<u32>(MemoryBase::BIOS)], sizeof(u16));
    } else if ((addr >= spramStart) && (addr < spramEnd)) {
        std::memcpy(&data, &iopSPRAM[addr - spramStart], sizeof(u16));
    } else {
        switch (addr) {
            default:
                std::printf("[Bus:IOP   ] Unhandled 16-bit read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

/* Returns a word from the IOP bus */
u32 readIOP32(u32 addr) {
    u32 data;

    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySizeIOP::RAM))) {
        std::memcpy(&data, &iopRAM[addr], sizeof(u32));
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::SIF), static_cast<u32>(MemorySize::SIF))) {
        return sif::readIOP(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::DMA0), static_cast<u32>(MemorySizeIOP::DMA))) {
        std::printf("[Bus:IOP   ] Unhandled 32-bit read @ 0x%08X (DMA)\n", addr);
        return 0;
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::Timer0), static_cast<u32>(MemorySizeIOP::Timer)) ||
               inRange(addr, static_cast<u32>(MemoryBaseIOP::Timer1), static_cast<u32>(MemorySizeIOP::Timer))) {
        return iop::timer::read32(addr);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::DMA1), static_cast<u32>(MemorySizeIOP::DMA))) {
        std::printf("[Bus:IOP   ] Unhandled 32-bit read @ 0x%08X (DMA)\n", addr);
        return 0;
    } else if (inRange(addr, static_cast<u32>(MemoryBase::BIOS), static_cast<u32>(MemorySize::BIOS))) {
        std::memcpy(&data, &bios[addr - static_cast<u32>(MemoryBase::BIOS)], sizeof(u32));
    } else if ((addr >= spramStart) && (addr < spramEnd)) {
        std::memcpy(&data, &iopSPRAM[addr - spramStart], sizeof(u32));
    } else {
        switch (addr) {
            case 0x1F801074:
                std::printf("[Bus:IOP   ] 32-bit read @ I_MASK\n");
                return intc::readMaskIOP();
            case 0x1F801078:
                //std::printf("[Bus:IOP   ] 32-bit read @ I_CTRL\n");
                return intc::readCtrlIOP();
            case 0x1F801010:
            case 0x1F801450:
                std::printf("[Bus:IOP   ] Unhandled 32-bit read @ 0x%08X\n", addr);
                return 0;
            default:
                std::printf("[Bus:IOP   ] Unhandled 32-bit read @ 0x%08X\n", addr);

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
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySize::RAM))) {
        memcpy(&ram[addr], &data, sizeof(u16));
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPIO), static_cast<u32>(MemorySize::BIOS))) {
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
        return ee::timer::write32(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IPU), static_cast<u32>(MemorySize::IPU))) {
        return ee::ipu::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::GIF), static_cast<u32>(MemorySize::GIF))) {
        return gif::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::VIF0), static_cast<u32>(MemorySize::VIF))) {
        return vif[0]->write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::VIF1), static_cast<u32>(MemorySize::VIF))) {
        return vif[1]->write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::DMAC), static_cast<u32>(MemorySize::DMAC))) {
        return ee::dmac::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::SIF), static_cast<u32>(MemorySize::SIF))) {
        return sif::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::RDRAM), static_cast<u32>(MemorySize::RDRAM))) {
        return rdram::write(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBase::IOPRAM), static_cast<u32>(MemorySize::IOPRAM))) {
        memcpy(&iopRAM[addr - static_cast<u32>(MemoryBase::IOPRAM)], &data, sizeof(u32));
    } else {
        switch (addr) {
            case 0x1000F000:
                std::printf("[Bus:EE    ] 32-bit write @ INTC_STAT = 0x%08X\n", data);
                return intc::writeStat(data);
            case 0x1000F010:
                std::printf("[Bus:EE    ] 32-bit write @ INTC_MASK = 0x%08X\n", data);
                return intc::writeMask(data);
            case 0x1000F520:
                std::printf("[Bus:EE    ] 32-bit write @ D_ENABLEW = 0x%08X\n", data);
                return ee::dmac::writeEnable(data);
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
            case 0x1000F510:
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
    } else if (inRange(addr, static_cast<u32>(MemoryBase::VU1Code), static_cast<u32>(MemorySize::VU1))) {
        /* TODO: implement VU code1 writes */
    } else if (inRange(addr, static_cast<u32>(MemoryBase::GS), static_cast<u32>(MemorySize::GS))) {
        gs::writePriv64(addr, data);
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
    } else if (inRange(addr, static_cast<u32>(MemoryBase::VU0Code), static_cast<u32>(MemorySize::VU0))) {
        /* TODO: implement VU mem1 writes */
    } else if (inRange(addr, static_cast<u32>(MemoryBase::VU0Data), static_cast<u32>(MemorySize::VU0))) {
        /* TODO: implement VU mem1 writes */
    } else if (inRange(addr, static_cast<u32>(MemoryBase::VU1Data), static_cast<u32>(MemorySize::VU1))) {
        /* TODO: implement VU mem1 writes */
    } else {
        switch (addr) {
            case 0x10004000:
                std::printf("[Bus:EE    ] 128-bit write @ VIF0_FIFO = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);
                break;
            case 0x10005000:
                std::printf("[Bus:EE    ] 128-bit write @ VIF1_FIFO = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);
                break;
            case 0x10006000:
                std::printf("[Bus:EE    ] 128-bit write @ GIF_FIFO = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);
                break;
            case 0x10007010:
                std::printf("[Bus:EE    ] 128-bit write @ IPU_IN_FIFO = 0x%016llX%016llX\n", data._u64[1], data._u64[0]);
                break;
            default:
                std::printf("[Bus:EE    ] Unhandled 128-bit write @ 0x%08X = 0x%016llX%016llX\n", addr, data._u64[1], data._u64[0]);

                exit(0);
        }
    }
}

/* Writes a byte to the IOP bus */
void writeIOP8(u32 addr, u8 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySizeIOP::RAM))) {
        iopRAM[addr] = data;
    } else if ((addr >= spramStart) && (addr < spramEnd)) {
        iopSPRAM[addr] = data;
    } else {
        switch (addr) {
            case 0x1F802070:
                std::printf("[Bus:IOP   ] Unhandled 8-bit write @ 0x%08X = 0x%02X\n", addr, data);
                break;
            default:
                std::printf("[Bus:IOP   ] Unhandled 8-bit write @ 0x%08X = 0x%02X\n", addr, data);

                exit(0);
        }
    }
}

/* Writes a halfword to the IOP bus */
void writeIOP16(u32 addr, u16 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySizeIOP::RAM))) {
        memcpy(&iopRAM[addr], &data, sizeof(u16));
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::DMA0), static_cast<u32>(MemorySizeIOP::DMA))) {
        std::printf("[Bus:IOP   ] Unhandled 16-bit write @ 0x%04X (DMA) = 0x%08X\n", addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::Timer0), static_cast<u32>(MemorySizeIOP::Timer)) ||
               inRange(addr, static_cast<u32>(MemoryBaseIOP::Timer1), static_cast<u32>(MemorySizeIOP::Timer))) {
        return iop::timer::write16(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::DMA1), static_cast<u32>(MemorySizeIOP::DMA))) {
        std::printf("[Bus:IOP   ] Unhandled 16-bit write @ 0x%04X (DMA) = 0x%08X\n", addr, data);
    } else if ((addr >= spramStart) && (addr < spramEnd)) {
        memcpy(&iopSPRAM[addr - spramStart], &data, sizeof(u16));
    } else {
        switch (addr) {
            default:
                std::printf("[Bus:IOP   ] Unhandled 16-bit write @ 0x%08X = 0x%04X\n", addr, data);

                exit(0);
        }
    }
}

/* Writes a word to the IOP bus */
void writeIOP32(u32 addr, u32 data) {
    if (inRange(addr, static_cast<u32>(MemoryBase::RAM), static_cast<u32>(MemorySizeIOP::RAM))) {
        memcpy(&iopRAM[addr], &data, sizeof(u32));
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::SIF), static_cast<u32>(MemorySize::SIF))) {
        return sif::writeIOP(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::DMA0), static_cast<u32>(MemorySizeIOP::DMA))) {
        std::printf("[Bus:IOP   ] Unhandled 32-bit write @ 0x%08X (DMA) = 0x%08X\n", addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::Timer0), static_cast<u32>(MemorySizeIOP::Timer)) ||
               inRange(addr, static_cast<u32>(MemoryBaseIOP::Timer1), static_cast<u32>(MemorySizeIOP::Timer))) {
        return iop::timer::write32(addr, data);
    } else if (inRange(addr, static_cast<u32>(MemoryBaseIOP::DMA1), static_cast<u32>(MemorySizeIOP::DMA))) {
        std::printf("[Bus:IOP   ] Unhandled 32-bit write @ 0x%08X (DMA) = 0x%08X\n", addr, data);
    } else if ((addr >= spramStart) && (addr < spramEnd)) {
        memcpy(&iopSPRAM[addr - spramStart], &data, sizeof(u32));
    } else {
        switch (addr) {
            case 0x1F801074:
                std::printf("[Bus:IOP   ] 32-bit write @ I_MASK = 0x%08X\n", data);
                return intc::writeMaskIOP(data);
            case 0x1F801078:
                //std::printf("[Bus:IOP   ] 32-bit write @ I_CTRL = 0x%08X\n", data);
                return intc::writeCtrlIOP(data);
            case 0x1FFE0130:
                std::printf("[Bus:IOP   ] 32-bit write @ Cache Control = 0x%08X\n", data);
                break;
            case 0x1FFE0140:
                std::printf("[Bus:IOP   ] 32-bit write @ SPRAM End = 0x%08X\n", data);

                spramEnd = data;
                break;
            case 0x1FFE0144:
                std::printf("[Bus:IOP   ] 32-bit write @ SPRAM Start = 0x%08X\n", data);

                spramStart = data;
                break;
            case 0x1F801004: case 0x1F80100C:
            case 0x1F801010: case 0x1F801014: case 0x1F801018: case 0x1F80101C:
            case 0x1F801020:
            case 0x1F801060:
            case 0x1F801400: case 0x1F801404: case 0x1F801408: case 0x1F80140C:
            case 0x1F801410: case 0x1F801414: case 0x1F801418: case 0x1F80141C:
            case 0x1F801420:
            case 0x1F801450:
            case 0x1F8015F0:
            case 0x1F802070:
                std::printf("[Bus:IOP   ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);
                break;
            default:
                std::printf("[Bus:IOP   ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    }
}

}
