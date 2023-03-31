/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

/* CD-ROM core taken from Mari (https://github.com/ladystarbreeze/Mari) */

#include "cdrom.hpp"

#include <cassert>
#include <cstdio>
#include <fstream>
#include <queue>

#include "../dmac/dmac.hpp"
#include "../../intc.hpp"
#include "../../scheduler.hpp"

namespace ps2::iop::cdrom {

using Channel = dmac::Channel;
using Interrupt = intc::IOPInterrupt;

/* --- CDROM constants --- */

constexpr int SECTOR_SIZE = 2352;
constexpr int READ_SIZE   = 0x818;

constexpr i64 CPU_SPEED = 44100 * 0x300 * 8;
constexpr i64 READ_TIME_SINGLE = CPU_SPEED / 75;
constexpr i64 READ_TIME_DOUBLE = CPU_SPEED / (2 * 75);

constexpr u64 _1MS = CPU_SPEED / 1000;

constexpr i64 INT3_TIME = _1MS;

/* CDROM commands */
enum Command {
    GetStat   = 0x01,
    SetLoc    = 0x02,
    ReadN     = 0x06,
    Stop      = 0x08,
    Pause     = 0x09,
    Init      = 0x0A,
    Unmute    = 0x0C,
    SetFilter = 0x0D,
    SetMode   = 0x0E,
    GetLocL   = 0x10,
    GetLocP   = 0x11,
    GetTN     = 0x13,
    GetTD     = 0x14,
    SeekL     = 0x15,
    SeekP     = 0x16,
    Test      = 0x19,
    GetID     = 0x1A,
    ReadS     = 0x1B,
    ReadTOC   = 0x1E,
};

/* Sub commands */
enum SubCommand {
    GetBIOSDate = 0x20,
};

/* Seek parameters */
struct SeekParam {
    int mins, secs, sector;
};

/* --- CDROM  registers --- */

enum class Mode {
    CDDAOn     = 1 << 0,
    AutoPause  = 1 << 1,
    Report     = 1 << 2,
    XAFilter   = 1 << 3,
    Ignore     = 1 << 4,
    FullSector = 1 << 5,
    XAADPCMOn  = 1 << 6,
    Speed      = 1 << 7,
};

enum class Status {
    Error     = 1 << 0,
    MotorOn   = 1 << 1,
    SeekError = 1 << 2,
    IDError   = 1 << 3,
    ShellOpen = 1 << 4,
    Read      = 1 << 5,
    Seek      = 1 << 6,
    Play      = 1 << 7,
};

std::ifstream file;

u8 mode, stat;
u8 iEnable, iFlags; // Interrupt registers

u8 index; // CDROM  register index

u8 cmd; // Current CDROM  command

std::queue<u8> paramFIFO, responseFIFO;
std::queue<u8> queuedResp, lateResp;

int queuedIRQ = 0;
bool oldCmdWasSeekL = true;

SeekParam seekParam;

u8 readBuf[SECTOR_SIZE];
int readIdx;

u64 seekTarget;

u64 idSendIRQ; // Scheduler

void readSector();
void loadResponse();
void pushResponse(u8);

u8 getData8();

/* BCD to char conversion */
inline u32 toChar(u8 bcd) {
    assert(((bcd & 0xF0) <= 0x90) && ((bcd & 0xF) <= 9));

    return (bcd / 16) * 10 + (bcd % 16);
}

void sendIRQEvent(int irq) {
    if (iFlags) {
        assert(!queuedIRQ);

        std::printf("[CDROM     ] Queueing INT%d\n", irq);

        queuedIRQ = irq;

        return;
    }

    std::printf("[CDROM     ] INT%d\n", irq);

    iFlags = (u8)irq;

    if (iEnable & iFlags) intc::sendInterruptIOP(Interrupt::CDVD); // CD-ROM interrupts are the same as CDVD

    loadResponse();

    /* If this is an INT1, read sector and send new INT1 */
    if (irq == 1) {
        // Send status
        pushResponse(stat | static_cast<u8>(Status::Read));

        readSector();

        if (mode & static_cast<u8>(Mode::Speed)) {
            scheduler::addEvent(idSendIRQ, 1, READ_TIME_DOUBLE);
        } else {
            scheduler::addEvent(idSendIRQ, 1, READ_TIME_SINGLE);
        }
    }
}

void readSector() {
    auto &s = seekParam;

    /* Calculate seek target (in sectors) */
    const auto mm   = toChar(s.mins) * 60 * 75; // 1min = 60sec
    const auto ss   = toChar(s.secs) * 75; // 1min = 75 sectors
    const auto sect = toChar(s.sector);

    seekTarget = mm + ss + sect - 150; // Starts at 2s, subtract 150 sectors to get start

    std::printf("[CDROM     ] Seeking to [%02X:%02X:%02X] = %llu\n", s.mins, s.secs, s.sector, seekTarget);

    file.seekg(seekTarget * SECTOR_SIZE, std::ios_base::beg);

    file.read((char *)readBuf, SECTOR_SIZE);

    readIdx = (mode & static_cast<u8>(Mode::FullSector)) ? 0x0C : 0x18;

    s.sector++;

    /* Increment BCD values */
    if ((s.sector & 0xF) == 10) { s.sector += 0x10; s.sector &= 0xF0; }

    if (s.sector == 0x75) { s.secs++; s.sector = 0; }

    if ((s.secs & 0xF) == 10) { s.secs += 0x10; s.secs &= 0xF0; }

    if (s.secs == 0x60) { s.mins++; s.secs = 0; }

    if ((s.mins & 0xF) == 10) { s.mins += 0x10; s.mins &= 0xF0; }

    std::printf("[CDROM     ] Next seek to [%02X:%02X:%02X]\n", s.mins, s.secs, s.sector);
}

u8 readResponse() {
    assert(!responseFIFO.empty());

    const auto data = responseFIFO.front(); responseFIFO.pop();

    return data;
}

void pushResponse(u8 data) {
    queuedResp.push(data);
}

void pushLateResponse(u8 data) {
    lateResp.push(data);
}

void clearParameters() {
    while (!paramFIFO.empty()) paramFIFO.pop();
}

void clearResponse() {
    while (!responseFIFO.empty()) responseFIFO.pop();

    while (!queuedResp.empty()) queuedResp.pop();
    
    while (!lateResp.empty()) lateResp.pop();
}

void clearParameters();

void loadResponse() {
    while (!queuedResp.empty()) {
        responseFIFO.push(queuedResp.front());

        queuedResp.pop();
    }

    while (!lateResp.empty()) {
        queuedResp.push(lateResp.front());

        lateResp.pop();
    }
}

/* Get BIOS Date */
void cmdGetBIOSDate() {
    std::printf("[CDROM     ] Get BIOS Date\n");

    // Send date
    pushResponse(0x96);
    pushResponse(0x09);
    pushResponse(0x12);
    pushResponse(0xC2);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Get ID */
void cmdGetID() {
    std::printf("[CDROM     ] Get ID\n");

    if (paramFIFO.size()) {
        /* Too few/many parameters, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x20);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    // Send status
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);

    /* Licensed, Mode2 */
    pushLateResponse(0x02);
    pushLateResponse(0x00);
    pushLateResponse(0x20);
    pushLateResponse(0x00);

    pushLateResponse('M');
    pushLateResponse('A');
    pushLateResponse('R');
    pushLateResponse('I');

    // Send INT2
    scheduler::addEvent(idSendIRQ, 2, INT3_TIME + 30000);
}

/* Get Loc L - Returns position from header */
void cmdGetLocL() {
    std::printf("[CDROM     ] Get Loc L\n");

    if (!oldCmdWasSeekL) {
        /* Can't execute data mode GetLoc after audio seek, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x80);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    oldCmdWasSeekL = false;

    char buf[8];

    file.seekg(seekTarget * SECTOR_SIZE + 12, std::ios_base::beg);
    file.read(buf, 8);

    // Send information
    for (int i = 0; i < 8; i++) pushResponse(buf[i]);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Get Loc P - Returns position from subchannel Q */
void cmdGetLocP() {
    std::printf("[CDROM     ] Get Loc P\n");

    // Send information
    pushResponse(0x01);
    pushResponse(0x01);
    pushResponse(seekParam.mins);
    pushResponse(seekParam.secs);
    pushResponse(seekParam.sector);
    pushResponse(seekParam.mins);
    pushResponse(seekParam.secs);
    pushResponse(seekParam.sector);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Get Stat - Activate motor, set mode = 0x20, abort all commands */
void cmdGetStat() {
    std::printf("[CDROM     ] Get Stat\n");

    if (paramFIFO.size()) {
        /* Too many parameters, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x20);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    // Send status
    pushResponse(stat);

    // Clear shell open flag
    stat &= ~static_cast<u8>(Status::ShellOpen);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Get TD - Returns track start */
void cmdGetTD() {
    std::printf("[CDROM     ] Get TD\n");

    if (paramFIFO.size() != 1) {
        /* Too few/many parameters, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x20);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    const auto track = paramFIFO.front(); paramFIFO.pop();

    if (track > 0x26) {
        /* Too few/many parameters, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x10);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    // Send status
    pushResponse(stat);
    pushResponse(0);
    pushResponse(0);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Get TN - Returns first and last track number */
void cmdGetTN() {
    std::printf("[CDROM     ] Get TN\n");

    if (paramFIFO.size()) {
        /* Too many parameters, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x20);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    // Send status
    pushResponse(stat);
    pushResponse(0x01);
    pushResponse(0x01);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Read TOC - Reread TOC */
void cmdReadTOC() {
    std::printf("[CDROM     ] Read TOC\n");

    // Send status
    pushResponse(stat);

    // Send status
    pushLateResponse(stat | static_cast<u8>(Status::Read));

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);

    // Send INT2
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME + 20000);
}

/* Init - Activate motor, set mode = 0x20, abort all commands */
void cmdInit() {
    std::printf("[CDROM     ] Init\n");

    if (paramFIFO.size()) {
        /* Too many parameters, send error */
        clearParameters();

        pushResponse(stat | static_cast<u8>(Status::Error));
        pushResponse(0x20);

        return scheduler::addEvent(idSendIRQ, 5, INT3_TIME);
    }

    stat = static_cast<u8>(Status::MotorOn);

    // Send mode
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);

    mode = static_cast<u8>(Mode::FullSector);

    // Send mode
    pushLateResponse(stat);

    // Send INT2
    scheduler::addEvent(idSendIRQ, 2, INT3_TIME + 120 * _1MS);
}

/* Pause */
void cmdPause() {
    std::printf("[CDROM     ] Pause\n");

    scheduler::removeEvent(idSendIRQ); // Kill all pending CDROM events

    /* Clear response buffer(s) */
    clearResponse();

    // Send status
    pushResponse(stat);

    // Send INT3 and INT2
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
    scheduler::addEvent(idSendIRQ, 2, INT3_TIME + 70 * _1MS - 35 * _1MS * !!(mode & static_cast<u8>(Mode::Speed)));

    stat &= ~static_cast<u8>(Status::Read);

    // Send status
    pushLateResponse(stat);
}

/* ReadN - Read sector */
void cmdReadN() {
    std::printf("[CDROM     ] ReadN\n");

    // Send status
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);

    const auto int1Time = INT3_TIME + (mode & static_cast<u8>(Mode::Speed)) ? READ_TIME_DOUBLE : READ_TIME_SINGLE;

    scheduler::addEvent(idSendIRQ, 1, int1Time);

    stat |= static_cast<u8>(Status::Read);

    pushLateResponse(stat);
}

/* SeekL - Data mode seek */
void cmdSeekL() {
    std::printf("[CDROM     ] SeekL\n");

    // Send status
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);

    // Send status
    pushLateResponse(stat | static_cast<u8>(Status::Seek));

    // Send INT2
    scheduler::addEvent(idSendIRQ, 2, INT3_TIME + 2 * _1MS);
}

/* Set Filter - Sets XA filter */
void cmdSetFilter() {
    std::printf("[CDROM     ] Set Filter\n");

    paramFIFO.pop(); paramFIFO.pop();

    // Send status
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Set Loc - Sets seek parameters */
void cmdSetLoc() {
    std::printf("[CDROM     ] Set Loc\n");

    // Send status
    pushResponse(stat);

    /* Set minutes, seconds, sector */
    seekParam.mins   = paramFIFO.front(); paramFIFO.pop();
    seekParam.secs   = paramFIFO.front(); paramFIFO.pop();
    seekParam.sector = paramFIFO.front(); paramFIFO.pop();

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Set Mode - Sets CDROM mode */
void cmdSetMode() {
    std::printf("[CDROM     ] Set Mode\n");

    // Send status
    pushResponse(stat);

    mode = paramFIFO.front(); paramFIFO.pop();

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Stop */
void cmdStop() {
    std::printf("[CDROM     ] Stop\n");

    scheduler::removeEvent(idSendIRQ); // Kill all pending CDROM events

    /* Clear response buffer(s) */
    clearResponse();

    // Send status
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
    scheduler::addEvent(idSendIRQ, 2, CPU_SPEED);

    stat &= ~static_cast<u8>(Status::MotorOn);

    stat &= ~static_cast<u8>(Status::Read);

    // Send status
    pushLateResponse(stat);
}

/* Unmute */
void cmdUnmute() {
    std::printf("[CDROM     ] Unmute\n");

    // Send status
    pushResponse(stat);

    // Send INT3
    scheduler::addEvent(idSendIRQ, 3, INT3_TIME);
}

/* Handles sub commands */
void doSubCmd() {
    const auto cmd = paramFIFO.front(); paramFIFO.pop();

    switch (cmd) {
        case SubCommand::GetBIOSDate: cmdGetBIOSDate(); break;
        default:
            std::printf("[CDROM     ] Unhandled sub command 0x%02X\n", cmd);

            exit(0);
    }
}

/* Handles CDROM  commands */
void doCmd(u8 data) {
    cmd = data;

    switch (cmd) {
        case Command::GetStat  : cmdGetStat(); break;
        case Command::SetLoc   : cmdSetLoc(); break;
        case Command::ReadN    : cmdReadN(); break;
        case Command::Stop     : cmdStop(); break;
        case Command::Pause    : cmdPause(); break;
        case Command::Init     : cmdInit(); break;
        case Command::Unmute   : cmdUnmute(); break;
        case Command::SetFilter: cmdSetFilter(); break;
        case Command::SetMode  : cmdSetMode(); break;
        case Command::GetLocL  : cmdGetLocL(); break;
        case Command::GetLocP  : cmdGetLocP(); break;
        case Command::GetTN    : cmdGetTN(); break;
        case Command::GetTD    : cmdGetTD(); break;
        case Command::SeekL    : oldCmdWasSeekL = true;  cmdSeekL(); break;
        case Command::SeekP    : oldCmdWasSeekL = false; cmdSeekL(); break; // Should be fine?
        case Command::Test     : doSubCmd(); break;
        case Command::GetID    : cmdGetID(); break;
        case Command::ReadS    : cmdReadN(); break; // Should be fine?
        case Command::ReadTOC  : cmdReadTOC(); break;
        default:
            std::printf("[CDROM     ] Unhandled command 0x%02X\n", cmd);

            exit(0);
    }
}

void init(const char *isoPath) {
    // Open file
    file.open(isoPath, std::ios::in | std::ios::binary);

    if (!file.is_open()) {
        std::printf("[CDROM     ] Unable to open file \"%s\"\n", isoPath);

        exit(0);
    }

    file.unsetf(std::ios::skipws);

    /* Register scheduler events */
    idSendIRQ = scheduler::registerEvent([](int irq) { sendIRQEvent(irq); });
}

u8 read(u32 addr) {
    switch (addr) {
        case 0x1F801800:
            {
                //std::printf("[CDROM     ] 8-bit read @ STATUS\n");

                u8 data = index;

                data |= paramFIFO.empty() << 3;                  // Parameter FIFO empty
                data |= (paramFIFO.size() != 16) << 4;           // Parameter FIFO not full
                data |= !responseFIFO.empty() << 5;              // Response FIFO not empty
                data |= (readIdx && (readIdx < READ_SIZE)) << 6; // Data FIFO not empty

                return data;
            }
        case 0x1F801801:
            {
                std::printf("[CDROM     ] 8-bit read @ RESPONSE\n");

                return readResponse();
            }
        case 0x1F801802:
            {
                const auto data = getData8();

                std::printf("[CDROM     ] 8-bit read @ DATA = 0x%02X\n", data);

                return data;
            }
        case 0x1F801803:
            switch (index) {
                case 0:
                    std::printf("[CDROM     ] 8-bit read @ IE\n");
                    return iEnable;
                case 1:
                    //std::printf("[CDROM     ] 8-bit read @ IF = 0x%02X\n", iFlags);

                    return iFlags | 0xE0;
                default:
                    std::printf("[CDROM     ] Unhandled 8-bit read @ 0x%08X.%u\n", addr, index);

                    exit(0);
            }
            break;
        default:
            std::printf("[CDROM     ] Unhandled 8-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

u32 readDMAC() {
    assert(readIdx && (readIdx < READ_SIZE));

    u32 data;

    std::memcpy(&data, &readBuf[readIdx], 4);

    readIdx += 4;

    if (readIdx == READ_SIZE) readIdx = 0;

    return data;
}

void write(u32 addr, u8 data) {
    switch (addr) {
        case 0x1F801800:
            //std::printf("[CDROM     ] 8-bit write @ INDEX = 0x%02X\n", data);

            index = data & 3;
            break;
        case 0x1F801801:
            switch (index) {
                case 0:
                    std::printf("[CDROM     ] 8-bit write @ CMD = 0x%02X\n", data);

                    doCmd(data);
                    break;
                case 3:
                    std::printf("[CDROM     ] 8-bit write @ VOLR->L = 0x%02X\n", data);
                    break;
                default:
                    std::printf("[CDROM     ] Unhandled 8-bit write @ 0x%08X.%u = 0x%02X\n", addr, index, data);

                    exit(0);
            }
            break;
        case 0x1F801802:
            switch (index) {
                case 0:
                    std::printf("[CDROM     ] 8-bit write @ PARAM = 0x%02X\n", data);

                    assert(paramFIFO.size() < 16);

                    paramFIFO.push(data);
                    break;
                case 1:
                    std::printf("[CDROM     ] 8-bit write @ IE = 0x%02X\n", data);

                    iEnable = data & 0x1F;
                    break;
                case 2:
                    std::printf("[CDROM     ] 8-bit write @ VOLL->L = 0x%02X\n", data);
                    break;
                case 3:
                    std::printf("[CDROM     ] 8-bit write @ VOLR->R = 0x%02X\n", data);
                    break;
                default:
                    std::printf("[CDROM     ] Unhandled 8-bit write @ 0x%08X.%u = 0x%02X\n", addr, index, data);

                    exit(0);
            }
            break;
        case 0x1F801803:
            switch (index) {
                case 0:
                    std::printf("[CDROM     ] 8-bit write @ REQUEST = 0x%02X\n", data);

                    assert(!(data & (1 << 5)));
                    break;
                case 1:
                    std::printf("[CDROM     ] 8-bit write @ IF = 0x%02X\n", data);

                    iFlags &= (~data & 0x1F);

                    if (!iFlags && queuedIRQ) {
                        // Send queued INT
                        scheduler::addEvent(idSendIRQ, queuedIRQ, _1MS);

                        queuedIRQ = 0;
                    }
                    break;
                case 2:
                    std::printf("[CDROM     ] 8-bit write @ VOLL->R = 0x%02X\n", data);
                    break;
                case 3:
                    std::printf("[CDROM     ] 8-bit write @ APPLYVOL = 0x%02X\n", data);
                    break;
                default:
                    std::printf("[CDROM     ] Unhandled 8-bit write @ 0x%08X.%u = 0x%02X\n", addr, index, data);

                    exit(0);
            }
            break;
        default:
            std::printf("[CDROM     ] Unhandled 8-bit write @ 0x%08X = 0x%02X\n", addr, data);

            exit(0);
    }
}

u8 getData8() {
    assert(readIdx && (readIdx < READ_SIZE));

    const auto data = readBuf[readIdx++];

    if (readIdx == READ_SIZE) readIdx = 0;

    return data;
}

}
