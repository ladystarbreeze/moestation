/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "dmac.hpp"

#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstring>

#include "../cpu/cop0.hpp"
#include "../../scheduler.hpp"
#include "../../sif.hpp"
#include "../../bus/bus.hpp"
#include "../../iop/dmac/dmac.hpp"

namespace ps2::ee::dmac {

using IOPChannel = iop::dmac::Channel;

const char *chnNames[10] = {
    "VIF0", "VIF1", "PATH3", "IPU_FROM", "IPU_TO", "SIF0", "SIF1", "SIF2", "SPR_FROM", "SPR_TO"
};

enum Mode {
    Normal,
    Chain,
    Interleave,
};

/* Source chain tags */
enum class STag {
    REFE, CNT, NEXT, REF, REFS, CALL, RET, END,
};

/* Destination chain tags */
enum class DTag {
    CNT, CNTS, END = 7,
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
    bool meis; // MFIFO empty interrupt status
    bool beis; // Bus error interrupt status
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

/* DMAC scheduler event IDs */
u32 idTransferEnd, idSIF0Start, idSIF1Start;

void checkInterrupt();

void transferEndEvent(int chnID) {
    auto &chn  = channels[chnID];
    auto &chcr = channels[chnID].chcr;

    std::printf("[DMAC:EE   ] %s transfer end\n", chnNames[chnID]);
    
    chn.hasTag = false;
    chn.isTagEnd = false;

    chcr.str = false;

    /* Set interrupt pending flag, check for interrupts */

    stat.cis |= 1 << chnID;

    checkInterrupt();
}

void sif0StartEvent() {
    iop::dmac::setDRQ(IOPChannel::SIF0, true);
}

void sif1StartEvent() {
    iop::dmac::setDRQ(IOPChannel::SIF1, true);
}

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

/* Reads and decodes a source chain tag */
void readSourceTag(Channel chnID) {
    auto &chn  = channels[static_cast<int>(chnID)];
    auto &chcr = chn.chcr;

    /* Read DMAtag from memory */
    auto dmaTag = bus::readDMAC128(chn.tadr);

    /* Set QWC and TAG */
    chn.qwc  = dmaTag._u16[0];
    chcr.tag = dmaTag._u16[1];

    std::printf("[DMAC:EE   ] New DMAtag = 0x%016llX%016llX, QWC = %u\n", dmaTag._u64[1], dmaTag._u64[0], chn.qwc);

    /* Get tag ID */
    const auto tag = (STag)((dmaTag._u16[1] >> 12) & 3);

    switch (tag) {
        case STag::REFE:
            chn.madr  = dmaTag._u32[1] & ~15;
            chn.tadr += 16;

            chn.isTagEnd = true;

            std::printf("[DMAC:EE   ] REFE; MADR = 0x%08X, TADR = 0x%08X\n", chn.madr, chn.tadr);
            break;
        default:
            std::printf("[DMAC:EE   ] Unhandled Source Chain tag %d\n", tag);

            exit(0);
    }
}

/* Decodes a destination chain tag */
void decodeDestinationTag(Channel chnID, u64 dmaTag) {
    auto &chn  = channels[static_cast<int>(chnID)];
    auto &chcr = chn.chcr;

    /* Set QWC and TAG */
    chn.qwc  = dmaTag & 0xFFFF;
    chcr.tag = (dmaTag >> 16) & 0xFFFF;

    std::printf("[DMAC:EE   ] New DMAtag = 0x%016llX, QWC = %u\n", dmaTag, chn.qwc);

    /* Get tag ID */
    const auto tag = (DTag)((dmaTag >> 28) & 3);

    switch (tag) {
        case DTag::CNTS:
            chn.madr = (dmaTag >> 32) & ~15;

            chn.isTagEnd = dmaTag & (1 << 31) && chcr.tie;

            std::printf("[DMAC:EE   ] CNTS; MADR = 0x%08X, isTagEnd = %d\n", chn.madr, chn.isTagEnd);
            break;
        default:
            std::printf("[DMAC:EE   ] Unhandled Destination Chain tag %d\n", tag);

            exit(0);
    }
}

/* Performs SIF0 DMA */
void doSIF0() {
    const auto chnID = Channel::SIF0;

    auto &chn  = channels[static_cast<int>(chnID)];
    auto &chcr = chn.chcr;

    std::printf("[DMAC:EE   ] SIF0 transfer\n");

    /* SIF0 is always to RAM, in Chain mode */
    assert(chcr.mod == Mode::Chain);
    assert(!chcr.tte);

    if (!chn.qwc) { // Same as `if (!chn.hasTag)` because SIF0 only runs in Chain mode
        /* Read and decode DMAtag */
        const auto dmaTag = sif::readSIF0_64();

        decodeDestinationTag(chnID, dmaTag);

        assert(chn.qwc);
    }

    /* Transfer up to 8 quadwords at a time */

    auto qwc  = std::min((u16)(sif::getSIF0Size() / 4), std::min(chn.qwc, (u16)8));
    auto madr = chn.madr;

    assert(qwc);

    for (u16 i = 0; i < qwc; i++) {
        bus::writeDMAC128(madr + 16 * i, sif::readSIF0_128());
    }

    /* Update channel registers */
    chn.qwc  -= qwc;
    chn.madr += 16 * qwc;

    /* Clear DRQ */
    chn.drq = false;

    scheduler::addEvent(idSIF0Start, 0, 4 * qwc, true);

    if (!chn.qwc && chn.isTagEnd) {
        /* NOTE: no need to reschedule because the SIF0 Start event happens at the same time */
        scheduler::addEvent(idTransferEnd, static_cast<int>(chnID), 4 * qwc, false);
    }
}

/* Performs SIF1 DMA */
void doSIF1() {
    const auto chnID = Channel::SIF1;

    auto &chn  = channels[static_cast<int>(chnID)];
    auto &chcr = chn.chcr;

    std::printf("[DMAC:EE   ] SIF1 transfer\n");

    /* SIF1 is always from RAM, in Chain mode */
    assert(chcr.mod == Mode::Chain);

    if (!chn.qwc) { // Same as `if (!chn.hasTag)` because SIF1 only runs in Chain mode
        /* Read and decode DMAtag */
        readSourceTag(chnID);

        assert(!chcr.tte); // No tag transfers?
        assert(chn.qwc);
    }

    /* Transfer up to 8 quadwords at a time */

    auto qwc  = std::min((u16)((32 - sif::getSIF1Size()) / 4), std::min(chn.qwc, (u16)8));
    auto madr = chn.madr;

    assert(qwc);

    for (u16 i = 0; i < qwc; i++) {
        sif::writeSIF1(bus::readDMAC128(madr + 16 * i));
    }

    /* Update channel registers */
    chn.qwc  -= qwc;
    chn.madr += 16 * qwc;

    /* Clear DRQ */
    chn.drq = false;

    scheduler::addEvent(idSIF1Start, 0, 4 * qwc, true);

    if (!chn.qwc && chn.isTagEnd) {
        /* NOTE: no need to reschedule because the SIF1 Start event happens at the same time */
        scheduler::addEvent(idTransferEnd, static_cast<int>(chnID), 4 * qwc, false);
    }
}

void startDMA(Channel chn) {
    switch (chn) {
        case Channel::SIF0: doSIF0(); break;
        case Channel::SIF1: doSIF1(); break;
        default:
            std::printf("[DMAC:EE   ] Unhandled channel %d DMA transfer\n", chn);

            exit(0);
    }
}

void checkInterrupt() {
    std::printf("[DMAC:EE   ] STAT.CIM = 0x%03X, STAT.CIS = 0x%03X\n", stat.cim, stat.cis);

    ee::cpu::cop0::setInterruptPendingDMAC(stat.cim & stat.cis);
}

void checkRunning(Channel chn) {
    const auto chnID = static_cast<int>(chn);

    std::printf("[DMAC:EE   ] Channel %d check\n", chnID);

    if ((enable & (1 << 16)) || !ctrl.dmae) {
        std::printf("[DMAC:EE   ] D_ENABLE = 0x%08X, D_CTRL.DMAE = %d\n", enable, ctrl.dmae);
        return;
    }

    std::printf("[DMAC:EE   ] D%d.DRQ = %d, PCR.PCE = %d, PCR.CDE%d = %d, D%d_CHCR.STR = %d\n", chnID, channels[chnID].drq, pcr.pce, chnID, pcr.cde & (1 << chnID), chnID, channels[chnID].chcr.str);

    if (channels[chnID].drq && (!pcr.pce || (pcr.cde & (1 << chnID))) && channels[chnID].chcr.str) startDMA(chn);
}

void checkRunningAll() {
    if ((enable & (1 << 16)) || !ctrl.dmae) {
        std::printf("[DMAC:EE   ] D_ENABLE = 0x%08X, D_CTRL.DMAE = %d\n", enable, ctrl.dmae);
        return;
    }

    for (int i = 0; i < 10; i++) {
        std::printf("[DMAC:EE   ] D%d.DRQ = %d, PCR.PCE = %d, PCR.CDE%d = %d, D%d_CHCR.STR = %d\n", i, channels[i].drq, pcr.pce, i, pcr.cde & (1 << i), i, channels[i].chcr.str);

        if (channels[i].drq && (!pcr.pce || (pcr.cde & (1 << i))) && channels[i].chcr.str) startDMA((Channel)i);
    }
}

void init() {
    std::memset(&channels, 0, 10 * sizeof(DMAChannel));

    /* Set initial DRQs */
    channels[static_cast<int>(Channel::VIF0   )].drq = true;
    channels[static_cast<int>(Channel::VIF1   )].drq = true;
    channels[static_cast<int>(Channel::PATH3  )].drq = true;
    channels[static_cast<int>(Channel::IPUTO  )].drq = true;
    channels[static_cast<int>(Channel::SIF1   )].drq = true;
    channels[static_cast<int>(Channel::SIF2   )].drq = true;
    channels[static_cast<int>(Channel::SPRFROM)].drq = true;
    channels[static_cast<int>(Channel::SPRTO  )].drq = true;

    /* Register scheduler events */

    idTransferEnd = scheduler::registerEvent([](int chnID, i64) { transferEndEvent(chnID); });
    idSIF0Start = scheduler::registerEvent([](int, i64) { sif0StartEvent(); });
    idSIF1Start = scheduler::registerEvent([](int, i64) { sif1StartEvent(); });
}

u32 read(u32 addr) {
    u32 data;

    if (addr < static_cast<u32>(ControlReg::CTRL)) {
        const auto chnID = static_cast<int>(getChannel(addr));

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
            case static_cast<u32>(ChannelReg::QWC):
                std::printf("[DMAC:EE   ] 32-bit read @ D%u_QWC\n", chnID);
                return chn.qwc;
            case static_cast<u32>(ChannelReg::TADR):
                std::printf("[DMAC:EE   ] 32-bit read @ D%u_TADR\n", chnID);
                return chn.tadr;
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
        const auto chnID = static_cast<int>(getChannel(addr));

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

                checkRunning(static_cast<Channel>(chnID));
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

                checkInterrupt();
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
    /*
    if (data & (1 << 16)) {
        std::printf("[DMAC:EE   ] Unhandled DMA suspension\n");

        exit(0);
    }
    */

    enable = data;

    checkRunningAll();
}

/* Sets DRQ, runs channel if enabled */
void setDRQ(Channel chn, bool drq) {
    channels[static_cast<int>(chn)].drq = drq;

    checkRunning(chn);
}

}
