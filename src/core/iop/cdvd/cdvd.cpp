/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "cdvd.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <queue>

#include "../dmac/dmac.hpp"
#include "../../intc.hpp"
#include "../../scheduler.hpp"

namespace ps2::iop::cdvd {

using Channel = dmac::Channel;
using Interrupt = intc::IOPInterrupt;

/* --- CDVD constants --- */

constexpr i64 IOP_CLOCK = 36864000; // 36.864 MHz

constexpr i64 READ_SPEED_CD  = 24 * 153600;
constexpr i64 READ_SPEED_DVD =  4 * 1382400;

/* --- CDVD registers --- */

enum CDVDReg {
    NCMD       = 0x1F402004,
    NCMDSTAT   = 0x1F402005,
    CDVDERROR  = 0x1F402006,
    CDVDISTAT  = 0x1F402008,
    SDRIVESTAT = 0x1F40200B,
    DISCTYPE   = 0x1F40200F,
    SCMD       = 0x1F402016,
    SCMDSTAT   = 0x1F402017,
    SCMDDATA   = 0x1F402018,
};

enum NCMD {
    ReadCD  = 0x06,
    ReadDVD = 0x08,
};

enum class NCMDStatus {
    ERROR = 1 << 0,
    READY = 1 << 6,
    BUSY  = 1 << 7,
};

enum SCMD {
    Subcommand        = 0x03,
    UpdateStickyFlags = 0x05,
    ReadRTC           = 0x08,
};

enum SubSCMD {
    MechaconVersion = 0x00,
};

enum class SCMDStatus {
    NODATA = 1 << 6,
    BUSY   = 1 << 7,
};

enum class DriveStatus {
    OPENED   = 1 << 0,
    SPINNING = 1 << 1,
    READING  = 1 << 2,
    PAUSED   = 1 << 3,
    SEEKING  = 1 << 4,
    ERROR    = 1 << 5,
};

struct SeekParam {
    i64 pos;  // Seeking position
    i64 num;  // Number of sectors to read
    i64 size; // Sector size

    i64 sectorNum = 0, oldSectorNum = 0; // For reads and seek timings
};

const char *isoPath = NULL;

std::ifstream file;

/* --- Read buffer --- */
u8  readBuf[2064];
int readIdx = 0;

/* --- N command registers --- */

u8 ncmdstat = static_cast<u8>(NCMDStatus::READY);
u8 ncmd;
std::queue<u8> ncmdParam;

/* --- S command registers --- */

u8 scmdstat = static_cast<u8>(SCMDStatus::NODATA);
u8 scmd;
std::queue<u8> scmdData;
std::queue<u8> scmdParam;

u8 drivestat = static_cast<u8>(DriveStatus::PAUSED), sdrivestat = static_cast<u8>(DriveStatus::PAUSED);

u8 istat = 0;

SeekParam seekParam;

/* GS scheduler event IDs */
u64 idFinishSeek, idRequestDMA;

i64 getBlockTiming(bool);
void doReadCD();

void finishSeekEvent() {
    //std::printf("[CDVD      ] Finished seeking\n");

    const auto isDVD = ncmd == NCMD::ReadDVD;

    if (isDVD) {
        std::printf("[CDVD      ] Unhandled DVD style reads\n");
        
        exit(0);
    } else {
        doReadCD();
    }

    //scheduler::addEvent(idRequestDMA, 0, getBlockTiming(isDVD), false);
    scheduler::addEvent(idRequestDMA, 0, getBlockTiming(isDVD), false); // Speed hack
}

void requestDMAEvent() {
    dmac::setDRQ(Channel::CDVD, true);
}

/* Sets DRIVESTAT and SDRIVESTAT */
void setDriveStatus(u8 stat) {
    drivestat = stat;

    sdrivestat |= drivestat;
}

/* Sends a CDVD interrupt */
void sendInterrupt() {
    setDriveStatus(static_cast<u8>(DriveStatus::PAUSED) | static_cast<u8>(DriveStatus::SPINNING));

    ncmdstat = static_cast<u8>(NCMDStatus::READY);

    istat |= 3;

    intc::sendInterruptIOP(Interrupt::CDVD);
}

/* Calculates block timing */
i64 getBlockTiming(bool isDVD) {
    if (isDVD) {
        return (IOP_CLOCK * seekParam.size) / READ_SPEED_DVD;
    }

    return (IOP_CLOCK * seekParam.size) / READ_SPEED_CD;
}

/* Calculates seek timings and sets drive status */
void doSeek() {
    std::printf("[CDVD      ] Seek; POS = %lld, NUM = %lld, SIZE = %lld\n", seekParam.pos, seekParam.num, seekParam.size);

    /* Calculate seek timings */

    const auto isDVD = ncmd == NCMD::ReadDVD;

    const auto delta = std::abs(seekParam.pos - seekParam.oldSectorNum);

    i64 seekCycles = IOP_CLOCK / 10; // Full seek
    if ((isDVD && (delta < 16)) || (!isDVD && (delta < 8))) {
        /* This is a contiguous read */
        seekCycles = getBlockTiming(isDVD) * delta;
    } else if ((isDVD && (delta < 14764)) || (!isDVD && (delta < 4371))) {
        /* This is a fast seek */
        seekCycles = IOP_CLOCK / 33;
    }

    /* Schedule seek */
    scheduler::addEvent(idFinishSeek, 0, 8 * seekCycles, true);

    if (delta) {
        setDriveStatus(static_cast<u8>(DriveStatus::SEEKING) | static_cast<u8>(DriveStatus::SPINNING));
    } else {
        setDriveStatus(static_cast<u8>(DriveStatus::READING));
    }
}

void doReadCD() {
    std::printf("[CDVD      ] Reading CD sector %lld\n", seekParam.pos + seekParam.sectorNum);

    setDriveStatus(static_cast<u8>(DriveStatus::READING));

    /* Seek to sector */

    const auto size = seekParam.size;

    const auto seekPos = size * (seekParam.pos + seekParam.sectorNum);

    file.seekg(seekPos, std::ios_base::beg);

    /* Read sector into buffer */

    file.read((char *)readBuf, size);

    readIdx = 0;
}

/* Performs a CD style read */
void ncmdReadCD() {
    std::printf("[CDVD      ] ReadCD\n");

    // POS = NCMDPARAM[3:0]
    u32 pos = 0;
    for (u32 i = 0; i < 4; i++) {
        pos |= (u32)ncmdParam.front() << (8 * i);

        ncmdParam.pop();
    }

    seekParam.pos = (i32)pos;

    assert(seekParam.pos >= 0); // Negative positions are possible, we don't handle those yet though

    // NUM = NCMDPARAM[7:4]
    u32 num = 0;
    for (u32 i = 0; i < 4; i++) {
        num |= (u32)ncmdParam.front() << (8 * i);

        ncmdParam.pop();
    }

    seekParam.num = num;

    assert(seekParam.num);

    // UNUSED = NCMDPARAM[9:8]
    ncmdParam.pop(); // Unused
    ncmdParam.pop(); // Unused

    // POS = NCMDPARAM[10]
    u8 size = ncmdParam.front();
    switch (size) {
        case 0: seekParam.size = 2048; break;
        default:
            std::printf("[CDVD      ] Unhandled sector size %u\n", size);

            exit(0);
    }

    ncmdParam.pop();

    doSeek();
}

/* Executes an N command */
void doNCMD() {
    ncmdstat = static_cast<u8>(NCMDStatus::BUSY);

    switch (ncmd) {
        case NCMD::ReadCD: ncmdReadCD(); break;
        default:
            std::printf("[CDVD      ] Unhandled N command 0x%02X\n", ncmd);

            exit(0);
    }
}

void scmdMechaconVersion() {
    std::printf("[CDVD      ] MechaconVersion\n");

    scmdData.push(0x03);
    scmdData.push(0x06);
    scmdData.push(0x02);
    scmdData.push(0x00);

    scmdstat &= ~static_cast<u8>(SCMDStatus::NODATA); // There is data now
}

void scmdReadRTC() {
    std::printf("[CDVD      ] ReadRTC\n");

    scmdData.push(0);
    scmdData.push(0);
    scmdData.push(0);
    scmdData.push(0);

    scmdData.push(0);
    scmdData.push(1);
    scmdData.push(0);
    scmdData.push(0);

    scmdstat &= ~static_cast<u8>(SCMDStatus::NODATA); // There is data now
}

void scmdUpdateStickyFlags() {
    std::printf("[CDVD      ] UpdateStickyFlags\n");

    /* Set SDRIVESTAT = DRIVESTAT */
    sdrivestat = drivestat;

    scmdData.push(0); // Successful

    scmdstat &= ~static_cast<u8>(SCMDStatus::NODATA); // There is data now
}

/* Executes an S command */
void doSCMD() {
    switch (scmd) {
        case SCMD::Subcommand:
            {
                const auto subcommand = scmdParam.front();

                scmdParam.pop();

                switch (subcommand) {
                    case SubSCMD::MechaconVersion: scmdMechaconVersion(); break;
                    default:
                        std::printf("[CDVD      ] Unhandled S subcommand 0x%02X\n", subcommand);

                        exit(0);
                }
            }
            break;
        case SCMD::UpdateStickyFlags: scmdUpdateStickyFlags(); break;
        case SCMD::ReadRTC          : scmdReadRTC(); break;
        default:
            std::printf("[CDVD      ] Unhandled S command 0x%02X\n", scmd);

            exit(0);
    }
}

void init(const char *path) {
    isoPath = path;

    // Open file
    file.open(isoPath, std::ios::in | std::ios::binary);

    if (!file.is_open()) {
        std::printf("[CDVD      ] Unable to open file \"%s\"\n", isoPath);

        exit(0);
    }

    file.unsetf(std::ios::skipws);

    /* Register CDVD events */
    idFinishSeek = scheduler::registerEvent([](int, i64) { finishSeekEvent(); });
    idRequestDMA = scheduler::registerEvent([](int, i64) { requestDMAEvent(); });
}

u8 read(u32 addr) {
    switch (addr) {
        case CDVDReg::NCMD:
            std::printf("[CDVD      ] 8-bit read @ NCMD\n");
            return ncmd;
        case CDVDReg::NCMDSTAT:
            //std::printf("[CDVD      ] 8-bit read @ NCMDSTAT\n");
            return ncmdstat;
        case CDVDReg::CDVDERROR:
            std::printf("[CDVD      ] 8-bit read @ CDVDERROR\n");
            return 0;
        case CDVDReg::CDVDISTAT:
            std::printf("[CDVD      ] 8-bit read @ CDVDISTAT\n");
            return istat;
        case CDVDReg::SDRIVESTAT:
            std::printf("[CDVD      ] 8-bit read @ SDRIVESTAT\n");
            return sdrivestat;
        case CDVDReg::DISCTYPE:
            std::printf("[CDVD      ] 8-bit read @ DISCTYPE\n");
            return 0x14; // PS2 DVD
        case CDVDReg::SCMD:
            std::printf("[CDVD      ] 8-bit read @ SCMD\n");
            return scmd;
        case CDVDReg::SCMDSTAT:
            std::printf("[CDVD      ] 8-bit read @ SCMDSTAT\n");
            return scmdstat;
        case CDVDReg::SCMDDATA:
            {
                std::printf("[CDVD      ] 8-bit read @ SCMDDATA\n");

                const auto data = scmdData.front();

                scmdData.pop();

                if (!scmdData.size()) scmdstat |= static_cast<u8>(SCMDStatus::NODATA); // All data has been read

                return data;
            }
        default:
            std::printf("[CDVD      ] Unhandled 8-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

u32 readDMAC() {
    i64 size = 2064; // DVD sector size
    if (ncmd == NCMD::ReadCD) {
        size = seekParam.size;
    }

    u32 data;
    std::memcpy(&data, &readBuf[readIdx], 4);

    readIdx += 4;

    if (readIdx == size) {
        seekParam.oldSectorNum = seekParam.pos + seekParam.sectorNum;

        seekParam.sectorNum++;

        if (seekParam.sectorNum == seekParam.num) {
            seekParam.sectorNum = 0;

            sendInterrupt();
        } else {
            finishSeekEvent();
        }
    }

    return data;
}

void write(u32 addr, u8 data) {
    switch (addr) {
        case CDVDReg::NCMD:
            std::printf("[CDVD      ] 8-bit write @ NCMD = 0x%02X\n", data);

            ncmd = data;

            doNCMD();
            break;
        case CDVDReg::NCMDSTAT:
            std::printf("[CDVD      ] 8-bit write @ NCMDPARAM = 0x%02X\n", data);

            ncmdParam.push(data);
            break;
        case CDVDReg::CDVDERROR:
            std::printf("[CDVD      ] 8-bit write @ 0x1F402006 (Unknown) = 0x%02X\n", data);
            break;
        case CDVDReg::CDVDISTAT:
            std::printf("[CDVD      ] 8-bit write @ CDVDISTAT = 0x%02X\n", data);

            istat &= ~data;
            break;
        case CDVDReg::SCMD:
            std::printf("[CDVD      ] 8-bit write @ SCMD = 0x%02X\n", data);

            scmd = data;

            doSCMD();
            break;
        case CDVDReg::SCMDSTAT:
            std::printf("[CDVD      ] 8-bit write @ SCMDPARAM = 0x%02X\n", data);

            scmdParam.push(data);
            break;
        default:
            std::printf("[CDVD      ] Unhandled 8-bit write @ 0x%08X = 0x%02X\n", addr, data);

            exit(0);
    }
}

void getExecPath(char *path) {
    static const char boot2Str[] = "BOOT2 = cdrom0:\\";

    char buf[64];

    // Check the beginning of the first 512 DVD sectors for the BOOT2 string
    for (int i = 0; i < 512; i++) {
        file.seekg(2048 * i, std::ios_base::beg);
        file.read(buf, sizeof(buf));

        if (std::strncmp(buf, boot2Str, 16) != 0) continue;

        std::memcpy(&path[9], &buf[16], 11);

        std::printf("[moestation] Executable path: \"%s\"\n", path);

        return;
    }

    std::printf("[moestation] Unable to find executable path\n");

    exit(0);
}

i64 getSectorSize() {
    if (ncmd == NCMD::ReadDVD) return 2064;

    return seekParam.size;
}

}
