/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "cdvd.hpp"

#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>

namespace ps2::iop::cdvd {

/* --- CDVD registers --- */

enum CDVDReg {
    NCMDSTAT = 0x1F402005,
};

enum NCMDStatus {
    ERROR = 1 << 0,
    READY = 1 << 6,
    BUSY  = 1 << 7,
};

const char *isoPath = NULL;

std::ifstream file;

u8 ncmdstat = NCMDStatus::READY;

void init(const char *path) {
    isoPath = path;

    // Open file
    file.open(isoPath, std::ios::binary);

    if (!file.is_open()) {
        std::printf("[CDVD      ] Unable to open file \"%s\"\n", isoPath);

        exit(0);
    }
}

u8 read(u32 addr) {
    switch (addr) {
        case CDVDReg::NCMDSTAT:
            std::printf("[CDVD      ] 8-bit read @ NCMDSTAT\n");
            return ncmdstat;
        default:
            std::printf("[CDVD      ] Unhandled 8-bit read @ 0x%08X\n", addr);

            exit(0);
    }
}

void getExecPath(char *path) {
    static const char boot2Str[] = "BOOT2 = cdrom0:\\";

    char buf[64];

    // Check the beginning of the first 512 DVD sectors for the BOOT2 string
    for (int i = 0; i < 512; i++) {
        file.seekg(2048 * i);
        file.read(buf, sizeof(buf));

        if (std::strncmp(buf, boot2Str, 16) != 0) continue;

        std::memcpy(&path[9], &buf[16], 11);

        std::printf("[moestation] Executable path: \"%s\"\n", path);

        return;
    }

    std::printf("[moestation] Unable to find executable path\n");

    exit(0);
}

}
