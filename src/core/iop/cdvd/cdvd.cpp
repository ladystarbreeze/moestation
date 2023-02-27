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

const char *isoPath = NULL;

std::ifstream file;

void init(const char *path) {
    isoPath = path;

    // Open file
    file.open(isoPath, std::ios::binary);

    if (!file.is_open()) {
        std::printf("[CDVD      ] Unable to open file \"%s\"\n", isoPath);

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
