cmake_minimum_required(VERSION 3.2)
project(moestation CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(-O3 -Wall -Wextra)

set(SOURCES
    src/main.cpp
    src/common/file.cpp
    src/core/intc.cpp
    src/core/moestation.cpp
    src/core/scheduler.cpp
    src/core/sif.cpp
    src/core/bus/bus.cpp
    src/core/bus/rdram.cpp
    src/core/ee/cpu/cop0.cpp
    src/core/ee/cpu/cpu.cpp
    src/core/ee/cpu/fpu.cpp
    src/core/ee/dmac/dmac.cpp
    src/core/ee/gif/gif.cpp
    src/core/ee/ipu/ipu.cpp
    src/core/ee/timer/timer.cpp
    src/core/ee/vif/vif.cpp
    src/core/ee/vu/vu.cpp
    src/core/ee/vu/vu_int.cpp
    src/core/gs/gs.cpp
    src/core/iop/cop0.cpp
    src/core/iop/iop.cpp
    src/core/iop/cdrom/cdrom.cpp
    src/core/iop/cdvd/cdvd.cpp
    src/core/iop/dmac/dmac.cpp
    src/core/iop/sio2/sio2.cpp
    src/core/iop/spu2/spu2.cpp
    src/core/iop/timer/timer.cpp
)

set(HEADERS
    src/common/file.hpp
    src/common/types.hpp
    src/core/intc.hpp
    src/core/moestation.hpp
    src/core/scheduler.hpp
    src/core/sif.hpp
    src/core/bus/bus.hpp
    src/core/bus/rdram.hpp
    src/core/ee/cpu/cop0.hpp
    src/core/ee/cpu/cpu.hpp
    src/core/ee/cpu/fpu.hpp
    src/core/ee/dmac/dmac.hpp
    src/core/ee/gif/gif.hpp
    src/core/ee/ipu/ipu.hpp
    src/core/ee/timer/timer.hpp
    src/core/ee/vif/vif.hpp
    src/core/ee/vu/vu.hpp
    src/core/ee/vu/vu_int.hpp
    src/core/gs/gs.hpp
    src/core/iop/cop0.hpp
    src/core/iop/iop.hpp
    src/core/iop/cdrom/cdrom.hpp
    src/core/iop/cdvd/cdvd.hpp
    src/core/iop/dmac/dmac.hpp
    src/core/iop/sio2/sio2.hpp
    src/core/iop/spu2/spu2.hpp
    src/core/iop/timer/timer.hpp
)

find_package(SDL2 REQUIRED)
include_directories(moestation ${SDL2_INCLUDE_DIRS})

add_executable(moestation ${SOURCES} ${HEADERS})
target_link_libraries(moestation ${SDL2_LIBRARIES})
