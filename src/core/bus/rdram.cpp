/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "rdram.hpp"

#include <cassert>
#include <cstdio>

/* --- RDRAM controller constants --- */

constexpr u8 MAX_RDRAM = 2; // ??

/* --- RDRAM registers --- */

/* RDRAM controller registers */
enum class RDRAMReg {
    INIT   = 0x021, // RDRAM initialization
    TEST34 = 0x022, // Test register
    DEVID  = 0x040, // Device ID, low 5 bits are effective
    CCA    = 0x043, // Current control A, low 8 bits are effective
    CCB    = 0x044, // Current control B, low 8 bits are effective
    NAPX   = 0x045, // NAP exit length phase A/B, low 11 bits are effective
    PDNXA  = 0x046, // PDN exit length phase A, low 6 bits are effective
    PDNX   = 0x047, // PDN exit length phase A + B, low 3 bits are effective
    TPARM  = 0x048, // t parameters, low 7 bits are effective
    TFRM1  = 0x049, // t_cycle framing parameter, low 4 bits are effective
    TCDLY1 = 0x04A, // t_cycle delay, low 2 bits are effective
    SKIP   = 0x04B, // Autoskip circuit configuration, bits 10-12 are effective
    TCYCLE = 0x04C, // t_cycle in 64 ps units, low 6 bits are effective
    TEST77 = 0x04D, // Test register
    TEST78 = 0x04E, // Test register
};

/* RDRAM initialization */
struct INIT {
    u8   sdevid = 0x3F;  // Serial DEVice IDentification
    bool psx;            // Power Select eXit
    bool srp    = true;  // Serial RePeat
    bool nsr    = false; // NAP Self Refresh
    bool psr    = false; // PDN Self Refresh
    bool lsr    = false; // Low-power Self Refresh (always 0?)
    bool ten    = false; // Temperature sensing ENable
    bool tsq;            // Temperature Sensing output
    bool dis    = false; // RDRAM DISable
};

/* RDRAM */
struct RDRAM {
    INIT init;
    u8   devid;
    u8   cca, ccb;
    u16  napx;
    u8   pdnxa;
    u8   pdnx;
    u8   tparm;
    u8   tfrm1;
    u8   tcdly1;
    u16  skip;
    u8   tcycle;
};

/* --- RDRAM commands --- */

/* RDRAM commands */
enum SerialOpcode {
    SRD  = 0x0, // Serial ReaD
    SWR  = 0x1, // Serial WRite
    SETR = 0x2, // SET Reset bit
    SETF = 0x4, // SET Fast clock mode
    CLRR = 0xB, // CLeaR Reset bit
};

/* RDRAM command packet */
struct CommandPacket {
    /* SD */
    u16 serialData;

    /* SA */
    u16 serialAddr;

    /* SRQ */
    u8   serialDev; // Serial device
    u8   serialOp;  // Serial opcode
    bool serialBc;  // Serial broadcast
};

RDRAM rdram[MAX_RDRAM];

CommandPacket cmdPacket;

u32 sioHI; // Data to return from SIO_HI reads

/* --- RDRAM read/write handlers --- */

/* Returns DEVID register */
void readDEVID() {
    const auto serialDev = cmdPacket.serialDev;

    std::printf("[RDRAM     ] Read @ DEVID (sdev %u)\n", serialDev);

    sioHI = 0;

    for (auto &r : rdram) {
        if (r.init.sdevid == serialDev) {
            sioHI = r.devid;

            return;
        }
    }

    std::printf("[RDRAM     ] No serial device found\n");
}

/* Returns INIT register */
void readINIT() {
    const auto serialDev = cmdPacket.serialDev;

    std::printf("[RDRAM     ] Read @ INIT (sdev %u)\n", serialDev);

    sioHI = 0;

    for (auto &r : rdram) {
        auto &init = r.init;

        if (init.sdevid == serialDev) {
            sioHI |= ((init.sdevid & 0x20) << 9) | (init.sdevid & 0x1F);
            sioHI |= init.psx <<  6;
            sioHI |= init.srp <<  7;
            sioHI |= init.nsr <<  8;
            sioHI |= init.psr <<  9;
            //sioHI |= init.lsr << 10;
            sioHI |= init.ten << 11;
            sioHI |= init.tsq << 12;
            sioHI |= init.dis << 13;

            return;
        }
    }

    std::printf("[RDRAM     ] No serial device found\n");
}

/* Returns an RDRAM register */
void readReg() {
    std::printf("[RDRAM     ] SRD\n");

    switch (cmdPacket.serialAddr) {
        case static_cast<u8>(RDRAMReg::INIT ): readINIT();  break;
        case static_cast<u8>(RDRAMReg::DEVID): readDEVID(); break;
        default:
            std::printf("[RDRAM     ] Unhandled read @ 0x%03X\n", cmdPacket.serialAddr);

            exit(0);
    }
}

/* Writes CCA register */
void writeCCA() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ CCA = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.cca = data & 0xFF;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ CCA (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes CCB register */
void writeCCB() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ CCB = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.ccb = data & 0xFF;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ CCB (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes DEVID register */
void writeDEVID() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Unhandled broadcast write @ DEVID = 0x%04X\n", data);

        exit(0);
    } else {
        const auto serialDev = cmdPacket.serialDev;

        std::printf("[RDRAM     ] Write @ DEVID (sdev %u) = 0x%04X\n", serialDev, data);

        for (auto &r : rdram) {
            if (serialDev == r.init.sdevid) {
                r.devid = data & 0x1F;

                return;
            }
        }

        std::printf("[RDRAM     ] No serial device found\n");
    }
}

/* Writes INIT register */
void writeINIT() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ INIT = 0x%04X\n", data);

        for (auto &r : rdram) {
            auto &init = r.init;

            init.sdevid = ((data >> 9) & 0x20) | (data & 0x1F);
            init.psx    = data & (1 <<  6);
            init.srp    = data & (1 <<  7);
            init.nsr    = data & (1 <<  8);
            init.psr    = data & (1 <<  9);
            //init.lsr    = data & (1 << 10); ??
            init.ten    = data & (1 << 11);
            init.tsq    = data & (1 << 12);
            init.dis    = data & (1 << 13);
        }
    } else {
        const auto serialDev = cmdPacket.serialDev;

        std::printf("[RDRAM     ] Write @ INIT (sdev %u) = 0x%04X\n", serialDev, data);

        for (auto &r : rdram) {
            auto &init = r.init;

            if (init.sdevid == serialDev) {
                init.sdevid = ((data >> 9) & 0x20) | (data & 0x1F);
                init.psx    = data & (1 <<  6);
                init.srp    = data & (1 <<  7);
                init.nsr    = data & (1 <<  8);
                init.psr    = data & (1 <<  9);
                //init.lsr    = data & (1 << 10); ??
                init.ten    = data & (1 << 11);
                init.tsq    = data & (1 << 12);
                init.dis    = data & (1 << 13);

                std::printf("[RDRAM     ] sdev %u is sdev %u now\n", serialDev, init.sdevid);

                return;
            }
        }

        std::printf("[RDRAM     ] No serial device found\n");
    }
}

/* Writes NAPX register */
void writeNAPX() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ NAPX = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.napx = data & 0x7FF;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ NAPX (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes PDNX register */
void writePDNX() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ PDNX = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.pdnx = data & 7;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ PDNX (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes PDNXA register */
void writePDNXA() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ PDNXA = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.pdnxa = data & 0x3F;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ PDNXA (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes SKIP register */
void writeSKIP() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ SKIP = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.skip = data & 0x1700;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ SKIP (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes TCDLY1 register */
void writeTCDLY1() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ TCDLY1 = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.tcdly1 = data & 3;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ TCDLY1 (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes TCYCLE register */
void writeTCYCLE() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ TCYCLE = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.tcycle = data & 0x3F;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ TCYCLE (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes TFRM1 register */
void writeTFRM1() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ TFRM1 = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.tfrm1 = data & 0xF;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ TFRM1 (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes TPARM register */
void writeTPARM() {
    const auto data = cmdPacket.serialData;

    if (cmdPacket.serialBc) {
        std::printf("[RDRAM     ] Broadcast write @ TPARM = 0x%04X\n", data);

        for (auto &r : rdram) {
            r.tparm = data & 0x7F;
        }
    } else {
        std::printf("[RDRAM     ] Unhandled write @ TPARM (sdev %u) = 0x%04X\n", cmdPacket.serialDev, data);

        exit(0);
    }
}

/* Writes an RDRAM register */
void writeReg() {
    std::printf("[RDRAM     ] SWR\n");

    switch (cmdPacket.serialAddr) {
        case static_cast<u8>(RDRAMReg::INIT  ): writeINIT();   break;
        case static_cast<u8>(RDRAMReg::TEST34):
            std::printf("[RDRAM     ] Write @ TEST34 = 0x%04X\n", cmdPacket.serialData);
            break;
        case static_cast<u8>(RDRAMReg::DEVID ): writeDEVID();  break;
        case static_cast<u8>(RDRAMReg::CCA   ): writeCCA();    break;
        case static_cast<u8>(RDRAMReg::CCB   ): writeCCB();    break;
        case static_cast<u8>(RDRAMReg::NAPX  ): writeNAPX();   break;
        case static_cast<u8>(RDRAMReg::PDNXA ): writePDNXA();  break;
        case static_cast<u8>(RDRAMReg::PDNX  ): writePDNX();   break;
        case static_cast<u8>(RDRAMReg::TPARM ): writeTPARM();  break;
        case static_cast<u8>(RDRAMReg::TFRM1 ): writeTFRM1();  break;
        case static_cast<u8>(RDRAMReg::TCDLY1): writeTCDLY1(); break;
        case static_cast<u8>(RDRAMReg::SKIP  ): writeSKIP();   break;
        case static_cast<u8>(RDRAMReg::TCYCLE): writeTCYCLE(); break; // Always 0x27?
        case static_cast<u8>(RDRAMReg::TEST77): // Write 0
            std::printf("[RDRAM     ] Write @ TEST77 = 0x%04X\n", cmdPacket.serialData);
            break;
        case static_cast<u8>(RDRAMReg::TEST78):
            std::printf("[RDRAM     ] Write @ TEST78 = 0x%04X\n", cmdPacket.serialData);
            break;
        default:
            std::printf("[RDRAM     ] Unhandled write @ 0x%03X = 0x%04X\n", cmdPacket.serialAddr, cmdPacket.serialData);

            exit(0);
    }
}

/* Executes an RDRAM command */
void doCmd() {
    switch (cmdPacket.serialOp) {
        case SerialOpcode::SRD : readReg();  break;
        case SerialOpcode::SWR : writeReg(); break;
        case SerialOpcode::SETR: std::printf("[RDRAM     ] SETR (sdev %u)\n", cmdPacket.serialDev); break;
        case SerialOpcode::SETF: std::printf("[RDRAM     ] SETF (sdev %u)\n", cmdPacket.serialDev); break;
        case SerialOpcode::CLRR: std::printf("[RDRAM     ] CLRR (sdev %u)\n", cmdPacket.serialDev); break;
        case 0xE: std::printf("[RDRAM     ] RSRV\n"); break; // SIO Reset? Bug?
        default:
            std::printf("[RDRAM     ] Unhandled serial opcode 0x%X\n", cmdPacket.serialOp);

            exit(0);
    }
}

namespace ps2::bus::rdram {

u32 read(u32 addr) {
    switch (addr) {
        case 0x1000F430:
            std::printf("[RDRAM     ] 32-bit read @ SIO_LO\n");
            return 0; // Always 0?
        case 0x1000F440:
            std::printf("[RDRAM     ] 32-bit read @ SIO_HI\n");
            return sioHI;
        default:
            std::printf("[RDRAM     ] Unhandled 32-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void write(u32 addr, u32 data) {
    switch (addr) {
        case 0x1000F430: // RDRAM command/register, broadcast, SDEV (SRQ/SA)
            std::printf("[RDRAM     ] 32-bit write @ SIO_LO = 0x%08X\n", data);

            cmdPacket.serialAddr = (data >> 16) & 0xFFF;

            cmdPacket.serialDev = ((data >> 5) & 0x20) | (data & 0x1F);
            cmdPacket.serialOp  = (data >> 6) & 0xF;
            cmdPacket.serialBc  = data & (1 << 5);

            doCmd();
            break;
        case 0x1000F440: // RDRAM data (SINT/SD)
            std::printf("[RDRAM     ] 32-bit write @ SIO_HI = 0x%08X\n", data);

            cmdPacket.serialData = data & 0xFFFF;
            break;
        default:
            std::printf("[RDRAM     ] Unhandled 32-bit write @ 0x%08X = 0x%08X\n", addr, data);

            exit(0);
    }
}

}
