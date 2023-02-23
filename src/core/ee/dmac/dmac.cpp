/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "dmac.hpp"

#include <cassert>
#include <cstdio>

/* DMA channels */
enum Channel {
    VIF0,    // Vector Interface 0
    VIF1,    // Vector Interface 1
    PATH3,   // Graphics Interface (PATH3)
    IPUFROM, // From Image Processing Unit
    IPUTO,   // To Image Processing Unit
    SIF0,    // Subsystem Interface (to IOP)
    SIF1,    // Subsystem Interface (from IOP)
    SIF2,    // Subsystem Interface
    SPRFROM, // From scratchpad
    SPRTO,   // To scratchpad
};

const char *chnNames[10] = {
    "VIF0", "VIF1", "PATH3", "IPU_FROM", "IPU_TO", "SIF0", "SIF1", "SIF2", "SPR_FROM", "SPR_TO"
};

/* --- DMAC registers --- */

/* DMA channel registers (0x1000xx00) */
enum class ChannelReg {
    CHCR = 0x10000000, // Channel control
    MADR = 0x10000010, // Memory address
    QWC  = 0x10000020, // Quadword count
    TADR = 0x10000030, // Tag address
    ASR0 = 0x10000040, // Address stack 0
    ASR1 = 0x10000050, // Address stack 1
    SADR = 0x10000080, // Stall address
};

/* DMA control registers */
enum class ControlReg {
    CTRL  = 0x1000E000, // Control
    STAT  = 0x1000E010, // Status
    PCR   = 0x1000E020, // Priority control
    SQWC  = 0x1000E030, // Stall quadword count
    RBSR  = 0x1000E040, // Ring buffer size
    RBOR  = 0x1000E050, // Ring buffer offset
    STADR = 0x1000E060, // Stall tag address
};

/* Returns DMA channel from address */
Channel getChannel(u32 addr) {
    switch ((addr >> 8) & 0xFF) {
        case 0x80: return Channel::VIF0;
        case 0x90: return Channel::VIF1;
        case 0xA0: return Channel::PATH3;
        case 0xB0: return Channel::IPUFROM;
        case 0xB4: return Channel::IPUTO;
        case 0xC0: return Channel::SIF0;
        case 0xC4: return Channel::SIF1;
        case 0xC8: return Channel::SIF2;
        case 0xD0: return Channel::SPRFROM;
        case 0xD4: return Channel::SPRTO;
        default:
            std::printf("[DMAC:EE   ] Invalid channel\n");

            exit(0);
    }
}

namespace ps2::ee::dmac {

void init() {
    /* TODO: set initial DMA requests */
}

u32 read(u32 addr) {
    if (addr < static_cast<u32>(ControlReg::CTRL)) {
        std::printf("[DMAC:EE   ] Unhandled 32-bit channel read @ 0x%08X\n", addr);

        exit(0);
    } else {
        switch (addr) {
            case static_cast<u32>(ControlReg::STAT):
                std::printf("[DMAC:EE   ] 32-bit read @ D_STAT\n");
                return 0;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit control read @ 0x%08X\n", addr);

                exit(0);
        }
    }
}

void write(u32 addr, u32 data) {
    if (addr < static_cast<u32>(ControlReg::CTRL)) {
        const auto chnId = static_cast<int>(getChannel(addr));

        switch (addr & ~(0xFF << 8)) {
            case static_cast<u32>(ChannelReg::CHCR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_CHCR = 0x%08X\n", chnId, data);
                break;
            case static_cast<u32>(ChannelReg::MADR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_MADR = 0x%08X\n", chnId, data);
                break;
            case static_cast<u32>(ChannelReg::TADR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_TADR = 0x%08X\n", chnId, data);
                break;
            case static_cast<u32>(ChannelReg::ASR0):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_ASR0 = 0x%08X\n", chnId, data);
                break;
            case static_cast<u32>(ChannelReg::ASR1):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_ASR1 = 0x%08X\n", chnId, data);
                break;
            case static_cast<u32>(ChannelReg::SADR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_SADR = 0x%08X\n", chnId, data);
                break;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit channel write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    } else {
        switch (addr) {
            case static_cast<u32>(ControlReg::CTRL):
                std::printf("[DMAC:EE   ] 32-bit write @ D_CTRL = 0x%08X\n", data);
                break;
            case static_cast<u32>(ControlReg::STAT):
                std::printf("[DMAC:EE   ] 32-bit write @ D_STAT = 0x%08X\n", data);
                break;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit control write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    }
}

}
