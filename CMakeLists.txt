cmake_minimum_required(VERSION 3.2)
project(moestation CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(-Wall -Wextra)

set(SOURCES
    src/main.cpp
    src/common/file.cpp
    src/core/moestation.cpp
    src/core/scheduler.cpp
    src/core/bus/bus.cpp
    src/core/bus/rdram.cpp
    src/core/ee/cpu/cop0.cpp
    src/core/ee/cpu/cpu.cpp
    src/core/ee/timer/timer.cpp
    src/core/gs/gs.cpp
)

set(HEADERS
    src/common/file.hpp
    src/common/types.hpp
    src/core/moestation.hpp
    src/core/scheduler.hpp
    src/core/bus/bus.hpp
    src/core/bus/rdram.hpp
    src/core/ee/cpu/cop0.hpp
    src/core/ee/cpu/cpu.hpp
    src/core/ee/timer/timer.hpp
    src/core/gs/gs.hpp
)

add_executable(moestation ${SOURCES} ${HEADERS})
