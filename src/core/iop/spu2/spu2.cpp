/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "spu2.hpp"

#include <cassert>
#include <cstdio>

#include "../dmac/dmac.hpp"

namespace ps2::iop::spu2 {

using Channel = dmac::Channel;

/* --- SPU2 registers --- */

enum class SPU2Reg {
    PMON     = 0x1F900180,
    NON      = 0x1F900184,
    VMIXL    = 0x1F900188,
    VMIXEL   = 0x1F90018C,
    VMIXR    = 0x1F900190,
    VMIXER   = 0x1F900194,
    MMIX     = 0x1F900198,
    COREATTR = 0x1F90019A,
    KON      = 0x1F9001A0,
    KOFF     = 0x1F9001A4,
    SPUADDR  = 0x1F9001A8,
    SPUDATA  = 0x1F9001AC,
    ADMASTAT = 0x1F9001B0,
    ESA      = 0x1F9002E0,
    EEA      = 0x1F90033C,
    ENDX     = 0x1F900340,
    CORESTAT = 0x1F900344,
};

enum class CoreStatus {
    DMAReq  = 1 << 7,
    DMABusy = 1 << 10,
};

u16 admaSTAT[2]; // AutoDMA status
u16 coreATTR[2]; // Core attributes
u16 coreSTAT[2]; // Core status

u32 spuADDR[2];

void setDMARequest(int coreID, bool drq) {
    if (drq) {
        std::printf("[SPU2:CORE%d] DMA request\n", coreID);

        if (coreID == 1) {
            dmac::setDRQ(Channel::SPU2, true);
        } else {
            dmac::setDRQ(Channel::SPU1, true);
        }

        coreSTAT[coreID] |= static_cast<u16>(CoreStatus::DMAReq);
    }
}

u16 read(u32 addr) {
    if ((addr >= 0x1F900760) && (addr < 0x1F9007B0)) {
        const auto coreID = (int)(addr >= 0x1F900788);

        std::printf("[SPU2:CORE%d] Unhandled 16-bit read @ 0x%08X (Volume/Reverb)\n", coreID, addr);

        return 0;
    } else if (addr >= 0x1F9007B0) {
        std::printf("[SPU2      ] Unhandled 16-bit read @ 0x%08X (Control)\n", addr);

        return 0;
    } else {
        const auto coreID = (int)(addr >= 0x1F900400);

        addr -= 0x400 * coreID;

        if (((addr >= 0x1F900180) && (addr < 0x1F9001C0)) || (addr >= 0x1F9002E0)) {
            switch (addr) {
                case static_cast<u32>(SPU2Reg::VMIXL):
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXL_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXL) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXL_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXEL):
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXEL_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXEL) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXEL_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXR):
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXR_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXR) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXR_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXER):
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXER_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::VMIXER) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ VMIXER_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::MMIX):
                    std::printf("[SPU2:CORE%d] 16-bit read @ MMIX\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::COREATTR):
                    std::printf("[SPU2:CORE%d] 16-bit read @ CORE_ATTR\n", coreID);
                    return coreATTR[coreID];
                case static_cast<u32>(SPU2Reg::KON):
                    std::printf("[SPU2:CORE%d] 16-bit read @ KON_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::KON) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ KON_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::KOFF):
                    std::printf("[SPU2:CORE%d] 16-bit read @ KOFF_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::KOFF) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ KOFF_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::SPUADDR):
                    std::printf("[SPU2:CORE%d] 16-bit read @ SPU_ADDR_HI\n", coreID);
                    return spuADDR[coreID] >> 16;
                case static_cast<u32>(SPU2Reg::SPUADDR) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ SPU_ADDR_LO\n", coreID);
                    return spuADDR[coreID];
                case static_cast<u32>(SPU2Reg::ADMASTAT):
                    std::printf("[SPU2:CORE%d] 16-bit read @ ADMA_STAT\n", coreID);
                    return admaSTAT[coreID];
                case static_cast<u32>(SPU2Reg::ESA):
                    std::printf("[SPU2:CORE%d] 16-bit read @ ESA_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::ESA) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ ESA_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::EEA):
                    std::printf("[SPU2:CORE%d] 16-bit read @ EEA_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::EEA) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ EEA_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::ENDX):
                    std::printf("[SPU2:CORE%d] 16-bit read @ ENDX_HI\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::ENDX) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit read @ ENDX_LO\n", coreID);
                    return 0;
                case static_cast<u32>(SPU2Reg::CORESTAT):
                    std::printf("[SPU2:CORE%d] 16-bit read @ CORE_STAT\n", coreID);
                    return coreSTAT[coreID];
                default:
                    std::printf("[SPU2:CORE%d] Unhandled 16-bit read @ 0x%08X\n", coreID, addr);

                    exit(0);
            }
        } else {
            std::printf("[SPU2:CORE%d] Unhandled 16-bit read @ 0x%08X (Voice)\n", coreID, addr);

            return 0;
        }
    }
}

u16 readPS1(u32 addr) {
    //std::printf("[SPU1      ] 16-bit read @ 0x%08X\n", addr);

    return 0;
}

void write(u32 addr, u16 data) {
    if ((addr >= 0x1F900760) && (addr < 0x1F9007B0)) {
        const auto coreID = (int)(addr >= 0x1F900788);

        std::printf("[SPU2:CORE%d] Unhandled 16-bit write @ 0x%08X (Volume/Reverb) = 0x%04X\n", coreID, addr, data);
    } else if (addr >= 0x1F9007B0) {
        std::printf("[SPU2      ] Unhandled 16-bit write @ 0x%08X (Control) = 0x%04X\n", addr, data);
    } else {
        const auto coreID = (int)(addr >= 0x1F900400);

        addr -= 0x400 * coreID;

        if ((addr >= 0x1F9002E4) && (addr < 0x1F90033C)) {
            std::printf("[SPU2:CORE%d] Unhandled 16-bit write @ 0x%08X = 0x%04X\n", coreID, addr, data);

            return;
        }

        if (((addr >= 0x1F900180) && (addr < 0x1F9001C0)) || (addr >= 0x1F9002E0)) {
            switch (addr) {
                case static_cast<u32>(SPU2Reg::PMON):
                    std::printf("[SPU2:CORE%d] 16-bit write @ PMON_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::PMON) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ PMON_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::NON):
                    std::printf("[SPU2:CORE%d] 16-bit write @ NON_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::NON) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ NON_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXL):
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXL_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXL) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXL_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXEL):
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXEL_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXEL) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXEL_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXR):
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXR_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXR) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXR_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXER):
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXER_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::VMIXER) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ VMIXER_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::MMIX):
                    std::printf("[SPU2:CORE%d] 16-bit write @ MMIX = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::COREATTR):
                    std::printf("[SPU2:CORE%d] 16-bit write @ CORE_ATTR = 0x%04X\n", coreID, data);

                    setDMARequest(coreID, ((data >> 4) & 3) == 2);

                    /* Clear DMA flags in CORE_STAT */
                    if (data & (1 << 15)) coreSTAT[coreID] &= ~(static_cast<u16>(CoreStatus::DMABusy) | static_cast<u16>(CoreStatus::DMAReq));

                    coreATTR[coreID] = data & 0x7FFF;
                    break;
                case static_cast<u32>(SPU2Reg::KON):
                    std::printf("[SPU2:CORE%d] 16-bit write @ KON_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::KON) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ KON_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::KOFF):
                    std::printf("[SPU2:CORE%d] 16-bit write @ KOFF_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::KOFF) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ KOFF_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::SPUADDR):
                    std::printf("[SPU2:CORE%d] 16-bit write @ SPU_ADDR_HI = 0x%04X\n", coreID, data);

                    spuADDR[coreID] = (spuADDR[coreID] & 0xFFFF) | ((data & 0xFF) << 16);
                    break;
                case static_cast<u32>(SPU2Reg::SPUADDR) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ SPU_ADDR_LO = 0x%04X\n", coreID, data);

                    spuADDR[coreID] = (spuADDR[coreID] & ~0xFFFF) | data;
                    break;
                case static_cast<u32>(SPU2Reg::SPUDATA):
                    std::printf("[SPU2:CORE%d] 16-bit write @ SPU_DATA = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::ADMASTAT):
                    std::printf("[SPU2:CORE%d] 16-bit write @ ADMA_STAT = 0x%04X\n", coreID, data);

                    admaSTAT[coreID] = data & ~3;

                    /* TODO: check if ADMA is running */
                    break;
                case static_cast<u32>(SPU2Reg::ESA):
                    std::printf("[SPU2:CORE%d] 16-bit write @ ESA_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::ESA) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ ESA_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::EEA):
                    std::printf("[SPU2:CORE%d] 16-bit write @ EEA_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::EEA) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ EEA_LO = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::ENDX):
                    std::printf("[SPU2:CORE%d] 16-bit write @ ENDX_HI = 0x%04X\n", coreID, data);
                    break;
                case static_cast<u32>(SPU2Reg::ENDX) + 2:
                    std::printf("[SPU2:CORE%d] 16-bit write @ ENDX_LO = 0x%04X\n", coreID, data);
                    break;
                default:
                    std::printf("[SPU2:CORE%d] Unhandled 16-bit write @ 0x%08X = 0x%04X\n", coreID, addr, data);

                    exit(0);
            }
        } else {
            std::printf("[SPU2:CORE%d] Unhandled 16-bit write @ 0x%08X (Voice) = 0x%04X\n", coreID, addr, data);
        }
    }
}

void writePS1(u32 addr, u16 data) {
    //std::printf("[SPU1      ] 16-bit write @ 0x%08X = 0x%04X\n", addr, data);

    return;
}

/* Clears DMA busy flags */
void transferEnd(int coreID) {
    coreSTAT[coreID] &= ~static_cast<u16>(CoreStatus::DMABusy);
}

}
