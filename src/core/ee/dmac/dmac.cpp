/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "dmac.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>

namespace ps2::ee::dmac {

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

/* D_CTRL */
struct CTRL {
    bool dmae; // DMA enable
    bool rele; // Release enable
    u8   mfd;  // Memory FIFO drain channel
    u8   sts;  // Stall control source channel
    u8   std;  // Stall control drain channel
    u8   rcyc; // Release cycle
};

/* D_PCR */
struct PCR {
    u16  cpc; // COP control
    u16  cde; // Channel DMA enable
    bool pce; // Priority control enable
};

/* D_STAT */
struct STAT {
    u16  cis;  // Channel interrupt status
    bool sis;  // Stall interrupt status
    bool meis; // MFIFP empty interrupt status
    bool beis; // Buss error interrupt status
    u16  cim;  // Channel interrupt mask
    bool sim;  // Stall interrupt mask
    bool meim; // MFIFO empty interrupt mask
};

/* D_CHCR */
struct ChannelControl {
    bool dir; // Direction
    u8   mod; // Mode
    u8   asp; // Address stack pointer
    bool tte; // Transfer tag enable
    bool tie; // Tag interrupt enable
    bool str; // Start
    u16  tag;
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

/* DMA channel */
struct DMAChannel {
    ChannelControl chcr;

    u32 madr, sadr, tadr; // Memory/Stall/Tag address
    u16 qwc;
    u32 asr0, asr1;

    bool drq;
    bool isTagEnd, hasTag;
};

DMAChannel channels[10]; // DMA channels

CTRL ctrl; // D_CTRL
PCR  pcr;  // D_PCR
STAT stat; // D_STAT

u32 enable = 0x1201; // D_ENABLE

void checkRunning(Channel chn) {
    std::printf("[DMAC:EE   ] Channel %d check\n", chn);

    if ((enable & (1 << 16)) || !ctrl.dmae) {
        std::printf("[DMAC:EE   ] D_ENABLE = 0x%08X, D_CTRL.DMAE = %d\n", enable, ctrl.dmae);
        return;
    }

    if (channels[chn].drq && channels[chn].chcr.str) {
        std::printf("[DMAC:EE   ] Unhandled channel %d DMA transfer\n", chn);

        exit(0);
    }

    std::printf("[DMAC:EE   ] D%d.DRQ = %d, PCR.PCE = %d, PCR.CDE%d = %d, D%d_CHCR.STR = %d\n", chn, channels[chn].drq, pcr.pce, chn, pcr.cde & (1 << chn), chn, channels[chn].chcr.str);
}

void checkRunningAll() {
    if ((enable & (1 << 16)) || !ctrl.dmae) {
        std::printf("[DMAC:EE   ] D_ENABLE = 0x%08X, D_CTRL.DMAE = %d\n", enable, ctrl.dmae);
        return;
    }

    for (int i = 0; i < 10; i++) {
        if (channels[i].drq && (!pcr.pce || (pcr.cde & (1 << i))) && channels[i].chcr.str) {
            std::printf("[DMAC:EE   ] Unhandled channel %d DMA transfer\n", i);

            exit(0);
        }

        std::printf("[DMAC:EE   ] D%d.DRQ = %d, PCR.PCE = %d, PCR.CDE%d = %d, D%d_CHCR.STR = %d\n", i, channels[i].drq, pcr.pce, i, pcr.cde & (1 << i), i, channels[i].chcr.str);
    }
}

void init() {
    std::memset(&channels, 0, 10 * sizeof(DMAChannel));

    /* Set initial DRQs */
    channels[Channel::VIF0   ].drq = true;
    channels[Channel::VIF1   ].drq = true;
    channels[Channel::PATH3  ].drq = true;
    channels[Channel::IPUTO  ].drq = true;
    channels[Channel::SIF1   ].drq = true;
    channels[Channel::SIF2   ].drq = true;
    channels[Channel::SPRFROM].drq = true;
    channels[Channel::SPRTO  ].drq = true;

    /* TODO: set initial DMA requests, register scheduler events */
}

u32 read(u32 addr) {
    u32 data;

    if (addr < static_cast<u32>(ControlReg::CTRL)) {
        const auto chnID = getChannel(addr);

        auto &chn = channels[chnID];

        switch (addr & ~(0xFF << 8)) {
            case static_cast<u32>(ChannelReg::CHCR):
                {
                    std::printf("[DMAC:EE   ] 32-bit read @ D%u_CHCR\n", chnID);

                    auto &chcr = chn.chcr;

                    data  = chcr.dir;
                    data |= chcr.mod << 2;
                    data |= chcr.asp << 4;
                    data |= chcr.tte << 6;
                    data |= chcr.tie << 7;
                    data |= chcr.str << 8;
                    data |= chcr.tag << 16;
                }
                break;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit channel read @ 0x%08X\n", addr);

                exit(0);
        }
    } else {
        switch (addr) {
            case static_cast<u32>(ControlReg::CTRL):
                std::printf("[DMAC:EE   ] 32-bit read @ D_CTRL\n");

                data  = ctrl.dmae;
                data |= ctrl.rele << 1;
                data |= ctrl.mfd  << 2;
                data |= ctrl.sts  << 4;
                data |= ctrl.std  << 6;
                data |= ctrl.rcyc << 8;
                break;
            case static_cast<u32>(ControlReg::STAT):
                std::printf("[DMAC:EE   ] 32-bit read @ D_STAT\n");

                data  = stat.cis;
                data |= stat.sis  << 13;
                data |= stat.meis << 14;
                data |= stat.beis << 15;
                data |= stat.cim  << 16;
                data |= stat.sim  << 29;
                data |= stat.meim << 30;
                break;
            case static_cast<u32>(ControlReg::PCR):
                std::printf("[DMAC:EE   ] 32-bit read @ D_PCR\n");

                data  = pcr.cpc;
                data |= pcr.cde << 16;
                data |= pcr.pce << 31;
                break;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit control read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

u32 readEnable() {
    return enable;
}

void write(u32 addr, u32 data) {
    if (addr < static_cast<u32>(ControlReg::CTRL)) {
        const auto chnID = getChannel(addr);

        auto &chn = channels[chnID];

        switch (addr & ~(0xFF << 8)) {
            case static_cast<u32>(ChannelReg::CHCR):
                {
                    std::printf("[DMAC:EE   ] 32-bit write @ D%u_CHCR = 0x%08X\n", chnID, data);

                    auto &chcr = chn.chcr;

                    chcr.dir = data & 1;
                    chcr.mod = (data >> 2) & 3;
                    chcr.asp = (data >> 4) & 3;
                    chcr.tte = data & (1 << 6);
                    chcr.tie = data & (1 << 7);
                    chcr.str = data & (1 << 8);
                }

                checkRunning(chnID);
                break;
            case static_cast<u32>(ChannelReg::MADR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_MADR = 0x%08X\n", chnID, data);

                chn.madr = data & ~15;
                break;
            case static_cast<u32>(ChannelReg::QWC):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_QWC = 0x%08X\n", chnID, data);
                
                chn.qwc = data;
                break;
            case static_cast<u32>(ChannelReg::TADR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_TADR = 0x%08X\n", chnID, data);

                chn.tadr = data & ~15;
                break;
            case static_cast<u32>(ChannelReg::ASR0):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_ASR0 = 0x%08X\n", chnID, data);

                chn.asr0 = data & ~15;
                break;
            case static_cast<u32>(ChannelReg::ASR1):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_ASR1 = 0x%08X\n", chnID, data);

                chn.asr1 = data & ~15;
                break;
            case static_cast<u32>(ChannelReg::SADR):
                std::printf("[DMAC:EE   ] 32-bit write @ D%u_SADR = 0x%08X\n", chnID, data);

                chn.sadr = data & ~15;
                break;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit channel write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    } else {
        switch (addr) {
            case static_cast<u32>(ControlReg::CTRL):
                std::printf("[DMAC:EE   ] 32-bit write @ D_CTRL = 0x%08X\n", data);

                ctrl.dmae = data & 1;
                ctrl.rele = data & 2;
                ctrl.mfd  = (data >> 2) & 3;
                ctrl.sts  = (data >> 4) & 3;
                ctrl.std  = (data >> 6) & 3;
                ctrl.rcyc = (data >> 8) & 7;

                checkRunningAll();
                break;
            case static_cast<u32>(ControlReg::STAT):
                std::printf("[DMAC:EE   ] 32-bit write @ D_STAT = 0x%08X\n", data);

                stat.cis = (stat.cis & ~data) & 0x3FF;
                stat.cim = (stat.cim ^ (data >> 16)) & 0x3FF;

                if (data & (1 << 13)) stat.sis  = false;
                if (data & (1 << 14)) stat.meis = false;
                if (data & (1 << 15)) stat.beis = false;
                if (data & (1 << 29)) stat.sim  = !stat.sim;
                if (data & (1 << 30)) stat.meim = !stat.meim;
                break;
            case static_cast<u32>(ControlReg::PCR):
                std::printf("[DMAC:EE   ] 32-bit write @ D_PCR = 0x%08X\n", data);

                pcr.cpc = data & 0x3FF;
                pcr.cde = (data >> 16) & 0x3FF;
                pcr.pce = data & (1 << 31);

                checkRunningAll();
                break;
            case static_cast<u32>(ControlReg::SQWC):
                std::printf("[DMAC:EE   ] 32-bit write @ D_SQWC = 0x%08X\n", data);
                break;
            case static_cast<u32>(ControlReg::RBSR):
                std::printf("[DMAC:EE   ] 32-bit write @ D_RBSR = 0x%08X\n", data);
                break;
            case static_cast<u32>(ControlReg::RBOR):
                std::printf("[DMAC:EE   ] 32-bit write @ D_RBOR = 0x%08X\n", data);
                break;
            default:
                std::printf("[DMAC:EE   ] Unhandled 32-bit control write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    }
}

void writeEnable(u32 data) {
    if (data & (1 << 16)) {
        std::printf("[DMAC:EE   ] Unhandled DMA suspension\n");

        exit(0);
    }

    enable = data;

    checkRunningAll();
}

/* Sets DRQ, runs channel if enabled */
void setDRQ(Channel chn, bool drq) {
    channels[chn].drq = drq;

    checkRunning(chn);
}

}
