/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#pragma once
#include <vector>

#include "types.hpp"

/* Reads a binary file into a std::vector */
std::vector<u8> loadBinary(const char *path);
