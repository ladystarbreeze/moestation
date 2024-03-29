/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include <cstdio>

#include "core/moestation.hpp"

int main(int argc, char **argv) {
    std::printf("[moestation] PlayStation 2 emulator\n");

    if (argc < 3) {
        std::printf("Usage: moestation /path/to/bios /path/to/executable [-PSXMODE]\n");

        return -1;
    }

    ps2::init(argv[1], argv[2], (argc == 4) ? argv[3] : NULL);
    ps2::run();

    return 0;
}
