/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "dmac.hpp"

#include <algorithm>
#include <cassert>
#include <cstdio>

#include "../../intc.hpp"
#include "../../scheduler.hpp"
#include "../../sif.hpp"
#include "../../bus/bus.hpp"
#include "../../ee/dmac/dmac.hpp"

namespace ps2::iop::dmac {

using EEChannel = ee::dmac::Channel;
using IOPInterrupt = intc::IOPInterrupt;

const char *chnNames[14] = {
    "MDEC_IN", "MDEC_OUT", "SIF2", "CDVD", "SPU1", "PIO", "OTC", "SPU2", "DEV9", "SIF0", "SIF1", "SIO2_IN", "SIO2_OUT", "USB",
};

enum Mode {
    Burst,
    Slice,
    LinkedList,
    Chain,
};

/* --- IOP DMA registers --- */

/* DMA channel registers */
enum class ChannelReg {
    MADR = 0x1F801000, // Memory address
    BCR  = 0x1F801004, // Block count
    CHCR = 0x1F801008, // Channel control
    TADR = 0x1F80100C, // Tag address
};

/* DMA control registers */
enum class ControlReg {
    DPCR      = 0x1F8010F0,
    DICR      = 0x1F8010F4,
    DPCR2     = 0x1F801570,
    DICR2     = 0x1F801574,
    DMACEN    = 0x1F801578,
    DMACINTEN = 0x1F80157C,
};

/* DMA Interrupt Control */
struct DICR {
    u8   sie; // Slice interrupt enable (CH0-6)
    bool bef; // Bus error flag
    u8   im;  // Interrupt mask (CH0-6)
    bool mie; // Master interrupt enable
    u8   ip;  // Interrupt pending (CH0-6)
    bool mif; // Master interrupt flag
};

/* DMA Interrupt Control 2 */
struct DICR2 {
    u16  tie; // Tag interrupt enable (CH4/9/10)
    u8   im;  // Interrupt mask (CH7-12)
    u8   ip;  // Interrupt pending (CH7-12)
};

/* D_CHCR */
struct ChannelControl {
    bool dir; // Direction
    bool dec; // Decrementing address
    bool tte; // Tag transfer enable
    u8   mod; // Mode
    u8   cpd; // Chopping window (DMA)
    u8   cpc; // Chopping window (CPU)
    bool str; // Start
    bool fst; // Forced start (don't wait for DRQ)
    bool spf; // IOP cache spoofing
};

/* DMA channel */
struct DMAChannel {
    ChannelControl chcr;

    u16 size, count; // Block count
    u32 madr, tadr;  // Memory/Tag address

    u32 len;

    bool drq;
    bool isTagEnd;
};

DMAChannel channels[14]; // DMA channels

/* DMA interrupt control */
DICR  dicr;
DICR2 dicr2;

u32 dpcr, dpcr2; // Priority control

bool dmacen = false; // DMAC enable

/* DMACINTEN */
bool cie = true;  // Channel interrupt enable
bool mid = false; // Master interrupt disable

/* DMAC scheduler event IDs */
u32 idTransferEnd, idSIF0Start, idSIF1Start;

void checkInterrupt();

void transferEndEvent(int chnID) {
    auto &chn  = channels[chnID];
    auto &chcr = channels[chnID].chcr;

    std::printf("[DMAC:IOP  ] %s transfer end\n", chnNames[chnID]);
    
    chn.isTagEnd = false;

    chcr.str = false;

    /* Set interrupt pending flag, check for interrupts */

    if (chnID < 7) {
        if (dicr.im & (1 << chnID)) dicr.ip |= 1 << chnID;
    } else {
        if (dicr2.im & (1 << (chnID - 7))) dicr2.ip |= 1 << (chnID - 7);
    }

    checkInterrupt();
}

void sif0StartEvent() {
    ee::dmac::setDRQ(EEChannel::SIF0, true);
}

void sif1StartEvent() {
    ee::dmac::setDRQ(EEChannel::SIF1, true);
}

/* Returns DMA channel from address */
Channel getChannel(u32 addr) {
    switch ((addr >> 4) & 0xFF) {
        case 0x08: return Channel::MDECIN;
        case 0x09: return Channel::MDECOUT;
        case 0x0A: return Channel::SIF2;
        case 0x0B: return Channel::CDVD;
        case 0x0C: return Channel::SPU1;
        case 0x0D: return Channel::PIO;
        case 0x0E: return Channel::OTC;
        case 0x50: return Channel::SPU2;
        case 0x51: return Channel::DEV9;
        case 0x52: return Channel::SIF0;
        case 0x53: return Channel::SIF1;
        case 0x54: return Channel::SIO2IN;
        case 0x55: return Channel::SIO2OUT;
        default:
            std::printf("[DMAC:IOP  ] Unknown channel\n");

            return Channel::Unknown;
    }
}

/* Performs SIF0 DMA */
void doSIF0() {
    const auto chnID = Channel::SIF0;

    auto &chn  = channels[static_cast<int>(chnID)];
    auto &chcr = chn.chcr;

    std::printf("[DMAC:IOP  ] SIF0 transfer\n");

    //assert(chcr.mod == Mode::Chain);

    assert(!chcr.dec);
    assert(chcr.tte);

    if (!chn.len) {
        auto dmaTag = (u64)bus::readDMAC32(chn.tadr) | ((u64)bus::readDMAC32(chn.tadr + 4) << 32);

        std::printf("[DMAC:IOP  ] New DMAtag = 0x%016llX\n", dmaTag);

        /* Transfer EEtag */

        sif::writeSIF0(bus::readDMAC32(chn.tadr + 8));
        sif::writeSIF0(bus::readDMAC32(chn.tadr + 12));

        chn.tadr += 16;

        /* Decode tag */

        chn.madr = dmaTag & 0xFFFFFC;
        chn.len  = (dmaTag >> 32) & 0xFFFFF;

        if (chn.len & 3) chn.len = (chn.len | 3) + 1; // Forcefully round up len

        chn.isTagEnd = dmaTag & (3 << 30);

        std::printf("[DMAC:IOP  ] MADR = 0x%06X, len = %u, isTagEnd = %d\n", chn.madr, chn.len, chn.isTagEnd);
    }

    /* Transfer up to 32 words at a time */
    const auto len = std::min((u32)(32 - sif::getSIF0Size()), std::min(chn.len, (u32)32));

    assert(len);

    for (u16 i = 0; i < len; i++) {
        sif::writeSIF0(bus::readDMAC32(chn.madr + 4 * i));
    }

    /* Update channel registers */
    chn.len  -= len;
    chn.madr += 4 * len;

    /* Clear DRQ */
    chn.drq = false;

    scheduler::addEvent(idSIF0Start, 0, 16 * len, true);

    if (!chn.len && chn.isTagEnd) {
        /* NOTE: no need to reschedule because the SIF0 Start event happens at the same time */
        scheduler::addEvent(idTransferEnd, static_cast<int>(chnID), 16 * len, false);
    }
}

/* Performs SIF1 DMA */
void doSIF1() {
    const auto chnID = Channel::SIF1;

    auto &chn  = channels[static_cast<int>(chnID)];
    auto &chcr = chn.chcr;

    std::printf("[DMAC:IOP  ] SIF1 transfer\n");

    //assert(chcr.mod == Mode::Chain);

    assert(!chcr.dec);
    assert(chcr.tte);

    if (!chn.len) {
        auto dmaTag = (u64)sif::readSIF1() | ((u64)sif::readSIF1() << 32);

        /* Remove excess tag words */

        (void)sif::readSIF1();
        (void)sif::readSIF1();

        std::printf("[DMAC:IOP  ] New DMAtag = 0x%016llX\n", dmaTag);

        /* Decode tag */

        chn.madr = dmaTag & 0xFFFFFC;
        chn.len  = (dmaTag >> 32) & 0xFFFFF;

        assert(!(chn.len & 3));

        chn.isTagEnd = dmaTag & (3 << 30);

        std::printf("[DMAC:IOP  ] MADR = 0x%06X, len = %u, isTagEnd = %d\n", chn.madr, chn.len, chn.isTagEnd);
    }

    /* Transfer up to 32 words at a time */
    const auto len = std::min((u32)sif::getSIF1Size(), std::min(chn.len, (u32)32));

    assert(len);

    for (u16 i = 0; i < len; i++) {
        bus::writeDMAC32(chn.madr + 4 * i, sif::readSIF1());
    }

    /* Update channel registers */
    chn.len  -= len;
    chn.madr += 4 * len;

    /* Clear DRQ */
    chn.drq = false;

    scheduler::addEvent(idSIF1Start, 0, 16 * len, true);

    if (!chn.len && chn.isTagEnd) {
        /* NOTE: no need to reschedule because the SIF1 Start event happens at the same time */
        scheduler::addEvent(idTransferEnd, static_cast<int>(chnID), 16 * len, false);
    }
}

void startDMA(Channel chn) {
    switch (chn) {
        case Channel::SIF0: doSIF0(); break;
        case Channel::SIF1: doSIF1(); break;
        default:
            std::printf("[DMAC:IOP  ] Unhandled channel %d (%s) transfer\n", chn, chnNames[static_cast<int>(chn)]);

            exit(0);
    }
}

/* Sets master interrupt flag, sends interrupt */
void checkInterrupt() {
    const auto oldMIF = dicr.mif;

    dicr.mif = cie && (dicr.bef || (dicr.mie && (dicr.ip || dicr2.ip)));
    
    std::printf("[DMAC:IOP  ] MIF = %d\n", dicr.mif);

    if (!oldMIF && dicr.mif && !mid) intc::sendInterruptIOP(IOPInterrupt::DMA);
}

void checkRunning(Channel chn) {
    const auto chnID = static_cast<int>(chn);

    std::printf("[DMAC:IOP  ] Channel %d check\n", chnID);

    if (!dmacen) {
        std::printf("[DMAC:IOP  ] DMACEN = %d\n", dmacen);
        return;
    }

    bool cde;
    if (chnID < 7) { cde = dpcr & (1 << (4 * chnID + 3)); } else { cde = dpcr2 & (1 << (4 * (chnID - 7) + 3)); }

    std::printf("[DMAC:IOP  ] D%d.DRQ = %d, DPCR.CDE%d = %d, D%d_CHCR.STR = %d, D%d_CHCR.FST = %d\n", chnID, channels[chnID].drq, chnID, cde, chnID, channels[chnID].chcr.str, chnID, channels[chnID].chcr.fst);

    if (channels[chnID].drq && cde && channels[chnID].chcr.str) startDMA(static_cast<Channel>(chnID));
}

void checkRunningAll() {
    if (!dmacen) {
        std::printf("[DMAC:IOP  ] DMACEN = %d\n", dmacen);
        return;
    }

    for (int i = 0; i < 13; i++) {
        bool cde;
        if (i < 7) { cde = dpcr & (1 << (4 * i + 3)); } else { cde = dpcr2 & (1 << (4 * (i - 7) + 3)); }

        std::printf("[DMAC:IOP  ] D%d.DRQ = %d, DPCR.CDE%d = %d, D%d_CHCR.STR = %d, D%d_CHCR.FST = %d\n", i, channels[i].drq, i, cde, i, channels[i].chcr.str, i, channels[i].chcr.fst);

        if ((channels[i].drq || channels[i].chcr.fst) && cde && channels[i].chcr.str) return startDMA(static_cast<Channel>(i));
    }
}

void init() {
    std::memset(&channels, 0, 14 * sizeof(DMAChannel));

    /* Set initial DRQs */
    channels[static_cast<int>(Channel::MDECIN)].drq = true;
    channels[static_cast<int>(Channel::SIF2  )].drq = true;
    channels[static_cast<int>(Channel::SIF0  )].drq = true;
    channels[static_cast<int>(Channel::SIO2IN)].drq = true;

    /* Register scheduler events */

    idTransferEnd = scheduler::registerEvent([](int chnID, i64) { transferEndEvent(chnID); });
    idSIF0Start = scheduler::registerEvent([](int, i64) { sif0StartEvent(); });
    idSIF1Start = scheduler::registerEvent([](int, i64) { sif1StartEvent(); });
}

u32 read32(u32 addr) {
    u32 data;

    if ((addr < static_cast<u32>(ControlReg::DPCR)) || ((addr > static_cast<u32>(ControlReg::DICR)) && (addr < static_cast<u32>(ControlReg::DPCR2)))) {
        const auto chnID = static_cast<int>(getChannel(addr));

        auto &chn = channels[chnID];

        switch (addr & ~(0xFF0)) {
            case static_cast<u32>(ChannelReg::CHCR):
                {
                    auto &chcr = chn.chcr;

                    std::printf("[DMAC:IOP  ] 32-bit read @ D%d_CHCR\n", chnID);

                    data  = chcr.dir;
                    data |= chcr.dec << 1;
                    data |= chcr.tte << 8;
                    data |= chcr.mod << 9;
                    data |= chcr.cpd << 16;
                    data |= chcr.cpc << 20;
                    data |= chcr.str << 24;
                    data |= chcr.fst << 28;
                    data |= chcr.spf << 30;
                }
                break;
            default:
                std::printf("[DMAC:IOP  ] Unhandled 32-bit channel read @ 0x%08X\n", addr);

                exit(0);
        }
    } else {
        switch (addr) {
            case static_cast<u32>(ControlReg::DPCR):
                std::printf("[DMAC:IOP  ] 32-bit read @ DPCR\n");
                return dpcr;
            case static_cast<u32>(ControlReg::DICR):
                std::printf("[DMAC:IOP  ] 32-bit read @ DICR\n");

                data  = dicr.sie;
                data |= dicr.bef << 15;
                data |= dicr.im  << 16;
                data |= dicr.mie << 23;
                data |= dicr.ip  << 24;
                data |= dicr.mif << 31;
                break;
            case static_cast<u32>(ControlReg::DPCR2):
                std::printf("[DMAC:IOP  ] 32-bit read @ DPCR2\n");
                return dpcr2;
            case static_cast<u32>(ControlReg::DICR2):
                std::printf("[DMAC:IOP  ] 32-bit read @ DICR2\n");

                data  = dicr2.tie;
                data |= dicr2.im << 16;
                data |= dicr2.ip << 24;
                break;
            case static_cast<u32>(ControlReg::DMACEN):
                std::printf("[DMAC:IOP  ] 32-bit read @ DMACEN\n");
                return dmacen;
            default:
                std::printf("[DMAC:IOP  ] Unhandled 32-bit control read @ 0x%08X\n", addr);

                exit(0);
        }
    }

    return data;
}

void write16(u32 addr, u16 data) {
    if ((addr < static_cast<u32>(ControlReg::DPCR)) || ((addr > static_cast<u32>(ControlReg::DICR)) && (addr < static_cast<u32>(ControlReg::DPCR2)))) {
        const auto chnID = static_cast<int>(getChannel(addr));

        auto &chn = channels[chnID];

        switch (addr & ~(0xFF0)) {
            case static_cast<u32>(ChannelReg::BCR):
                std::printf("[DMAC:IOP  ] 16-bit write @ D%u_BCR_LO = 0x%04X\n", chnID, data);

                chn.size = data;
                
                chn.len = (u32)chn.count * (u32)chn.size;
                break;
            case static_cast<u32>(ChannelReg::BCR) + 2:
                std::printf("[DMAC:IOP  ] 16-bit write @ D%u_BCR_HI = 0x%04X\n", chnID, data);

                chn.count = data;
                
                chn.len = (u32)chn.count * (u32)chn.size;
                break;
            default:
                std::printf("[DMAC:IOP  ] Unhandled 16-bit channel write @ 0x%04X = 0x%08X\n", addr, data);

                exit(0);
        }
    } else {
        std::printf("[DMAC:IOP  ] Unhandled 16-bit control write @ 0x%08X = 0x%04X\n", addr, data);

        exit(0);
    }
}

void write32(u32 addr, u32 data) {
    if ((addr < static_cast<u32>(ControlReg::DPCR)) || ((addr > static_cast<u32>(ControlReg::DICR)) && (addr < static_cast<u32>(ControlReg::DPCR2)))) {
        const auto chnID = static_cast<int>(getChannel(addr));

        auto &chn = channels[chnID];

        switch (addr & ~(0xFF0)) {
            case static_cast<u32>(ChannelReg::MADR):
                std::printf("[DMAC:IOP  ] 32-bit write @ D%u_MADR = 0x%08X\n", chnID, data);

                chn.madr = data & 0xFFFFFC;
                break;
            case static_cast<u32>(ChannelReg::BCR):
                std::printf("[DMAC:IOP  ] 32-bit write @ D%u_BCR = 0x%08X\n", chnID, data);

                chn.size  = data;
                chn.count = data >> 16;
                
                chn.len = (u32)chn.count * (u32)chn.size;
                break;
            case static_cast<u32>(ChannelReg::CHCR):
                {
                    auto &chcr = chn.chcr;

                    std::printf("[DMAC:IOP  ] 32-bit write @ D%u_CHCR = 0x%08X\n", chnID, data);

                    assert(!(data & (1 << 29)));

                    chcr.dir = data & (1 << 0);
                    chcr.dec = data & (1 << 1);
                    chcr.tte = data & (1 << 8);
                    chcr.mod = (data >>  9) & 3;
                    chcr.cpd = (data >> 16) & 7;
                    chcr.cpc = (data >> 20) & 7;
                    chcr.str = data & (1 << 24);
                    chcr.fst = data & (1 << 28);
                    chcr.spf = data & (1 << 30);
                }

                checkRunning(static_cast<Channel>(chnID));
                break;
            case static_cast<u32>(ChannelReg::TADR):
                std::printf("[DMAC:IOP  ] 32-bit write @ D%u_TADR = 0x%08X\n", chnID, data);

                chn.tadr = data & 0xFFFFFC;
                break;
            default:
                std::printf("[DMAC:IOP  ] Unhandled 32-bit channel write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    } else {
        switch (addr) {
            case static_cast<u32>(ControlReg::DPCR):
                std::printf("[DMAC:IOP  ] 32-bit write @ DPCR = 0x%08X\n", data);

                dpcr = data;

                checkRunningAll();
                break;
            case static_cast<u32>(ControlReg::DICR):
                std::printf("[DMAC:IOP  ] 32-bit write @ DICR = 0x%08X\n", data);

                dicr.sie = data & 0x3F;
                dicr.bef = data & (1 << 15); // Is this correct???
                dicr.im  = (data >> 16) & 0x3F;
                dicr.mie = data & (1 << 23);
                dicr.ip  = (dicr.ip & ~(data >> 24)) & 0x3F;

                checkInterrupt();
                break;
            case static_cast<u32>(ControlReg::DPCR2):
                std::printf("[DMAC:IOP  ] 32-bit write @ DPCR2 = 0x%08X\n", data);

                dpcr2 = data;

                checkRunningAll();
                break;
            case static_cast<u32>(ControlReg::DICR2):
                std::printf("[DMAC:IOP  ] 32-bit write @ DICR2 = 0x%08X\n", data);

                dicr2.tie = data & 0x610; // Only bits 4, 9 and 10 can be set
                dicr2.im  = (data >> 16) & 0x1F;
                dicr2.ip  = (dicr.ip & ~(data >> 24)) & 0x1F;

                checkInterrupt();
                break;
            case static_cast<u32>(ControlReg::DMACEN):
                std::printf("[DMAC:IOP  ] 32-bit write @ DMACEN = 0x%08X\n", data);

                dmacen = data & 1;

                checkRunningAll();
                break;
            default:
                std::printf("[DMAC:IOP  ] Unhandled 32-bit control write @ 0x%08X = 0x%08X\n", addr, data);

                exit(0);
        }
    }
}

/* Sets DRQ, runs channel if enabled */
void setDRQ(Channel chn, bool drq) {
    channels[static_cast<int>(chn)].drq = drq;

    checkRunning(chn);
}

}
