//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! main.zig
//!

const std = @import("std");

const err  = std.log.err;
const info = std.log.info;

const SDL = @import("sdl2");

// Submodules
const bus      = @import("core/bus.zig");
const cdvd     = @import("core/cdvd.zig");
const cpu      = @import("core/cpu.zig");
const dmac     = @import("core/dmac.zig");
const dmacIop  = @import("core/dmac_iop.zig");
const gif      = @import("core/gif.zig");
const gs       = @import("core/gs.zig");
const iop      = @import("core/iop.zig");
const spu2     = @import("core/spu2.zig");
const timer    = @import("core/timer.zig");
const timerIop = @import("core/timer_iop.zig");
const vif1     = @import("core/vif1.zig");

/// BIOS path
const biosPath = "moeFiles/scph39001.bin";
const cdvdPath = "moeFiles/planetarian.iso";
const elfPath  = "moeFiles/vu1_demo.elf";

const Controller = struct {
    nSelect: u1 = 1,
        nL3: u1 = 1,
        nR3: u1 = 1,
     nStart: u1 = 1,
        nUp: u1 = 1,
     nRight: u1 = 1,
      nDown: u1 = 1,
      nLeft: u1 = 1,
        nL2: u1 = 1,
        nR2: u1 = 1,
        nL1: u1 = 1,
        nR1: u1 = 1,
       nTri: u1 = 1,
    nCircle: u1 = 1,
     nCross: u1 = 1,
    nSquare: u1 = 1,
};

/// SDL screen
const Screen = struct {
    width : c_int = 0,
    height: c_int = 0,
    stride: c_int = 0,

    texture : ?*SDL.SDL_Texture  = null,
    renderer: ?*SDL.SDL_Renderer = null,
};

var screen: Screen = Screen{};

var controller: Controller = Controller{};

pub var shouldRun = true;

/// Taken from SDL.zig
fn sdlPanic() noreturn {
    const str = @as(?[*:0]const u8, SDL.SDL_GetError()) orelse "unknown error";
    @panic(std.mem.sliceTo(str, 0));
}

/// main()
pub fn main() void {
    // Initialize SDL
    if (SDL.SDL_Init(SDL.SDL_INIT_VIDEO) < 0) {
        sdlPanic();
    }
    defer SDL.SDL_Quit();

    // Set up window
    screen.width  = 640;
    screen.height = 480;

    screen.stride = 4;

    // Create window
    var window = SDL.SDL_CreateWindow(
        "moestation",
        SDL.SDL_WINDOWPOS_CENTERED, SDL.SDL_WINDOWPOS_CENTERED,
        screen.width, screen.height,
        SDL.SDL_WINDOW_SHOWN,
    ) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyWindow(window);

    screen.renderer = SDL.SDL_CreateRenderer(window, -1, SDL.SDL_RENDERER_ACCELERATED) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyRenderer(screen.renderer);

    if (SDL.SDL_RenderSetLogicalSize(screen.renderer, screen.width, screen.height) < 0) {
        sdlPanic();
    }

    if(SDL.SDL_SetHint(SDL.SDL_HINT_RENDER_VSYNC, "1") < 0) {
        sdlPanic();
    }

    screen.texture = SDL.SDL_CreateTexture(
        screen.renderer,
        SDL.SDL_PIXELFORMAT_XBGR8888, SDL.SDL_TEXTUREACCESS_STREAMING,
        screen.width, screen.height
    ) orelse sdlPanic();
    defer _ = SDL.SDL_DestroyTexture(screen.texture);

    info("   [moestation] BIOS file: {s}", .{biosPath});

    // Get allocator
    var allocator = std.heap.page_allocator;

    // Initialize submodules
    if (bus.init(allocator, biosPath, elfPath)) |_| {} else |e| switch (e) {
        error.FileNotFound => return err("  [moestation] Unable to find file.", .{}),
        else => return err("  [moestation] Unhandled error {}.", .{e})
    }
    defer bus.deinit(allocator);

    if (cdvd.init(cdvdPath)) |_| {} else |e| switch (e) {
        error.FileNotFound => return err("  [moestation] Unable to find ISO.", .{}),
        else => return err("  [moestation] Unhandled error {}.", .{e})
    }
    defer cdvd.deinit();

    if (gs.init(allocator)) |_| {} else |e| switch (e) {
        else => return err("  [moestation] Unhandled error {}.", .{e})
    }
    defer gs.deinit(allocator);

    cpu.init();
    dmac.init();
    dmacIop.init();
    iop.init();

    SDL.SDL_ShowWindow(window);

    while (shouldRun) {
        var i: i32 = 0;
        while (i < 4) : (i += 1) {
            cpu.step();
            cpu.step();

            cpu.vu[1].step();
            cpu.vu[1].step();

            dmac.checkRunning();

            gif.step();
            vif1.step();

            timer.step();
        }

        gs.step(4);
        spu2.step(4);

        iop.step();
        timerIop.step();
        cdvd.step();
        dmacIop.checkRunning();
    }
}

/// Polls input
pub fn poll() bool {
    const keyState = SDL.SDL_GetKeyboardState(null);

    var e: SDL.SDL_Event = undefined;

    if (SDL.SDL_PollEvent(&e) != 0) {
        switch (e.type) {
            SDL.SDL_QUIT => return false,
            SDL.SDL_KEYDOWN, SDL.SDL_KEYUP => {
                controller.nSelect = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_c)] == 0);
                controller.nStart  = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_v)] == 0);
                controller.nUp     = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_w)] == 0);
                controller.nRight  = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_d)] == 0);
                controller.nDown   = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_s)] == 0);
                controller.nLeft   = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_a)] == 0);
                controller.nL1     = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_q)] == 0);
                controller.nR1     = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_e)] == 0);
                controller.nL2     = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_1)] == 0);
                controller.nR2     = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_2)] == 0);
                controller.nTri    = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_i)] == 0);
                controller.nCircle = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_l)] == 0);
                controller.nCross  = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_k)] == 0);
                controller.nSquare = @bitCast(u1, keyState[SDL.SDL_GetScancodeFromKey(SDL.SDLK_j)] == 0);
            },
            else => {},
        }
    }

    return true;
}

/// Renders PS2 VRAM
pub fn renderScreen(fb: *u8) void {
    if (SDL.SDL_UpdateTexture(screen.texture, null, fb, screen.width * screen.stride) < 0) {
        sdlPanic();
    }

    if (SDL.SDL_RenderCopy(screen.renderer, screen.texture, null, null) < 0) {
        sdlPanic();
    }

    SDL.SDL_RenderPresent(screen.renderer);
}

pub fn getController() u16 {
    var data: u16 = 0;

    data |= @as(u16, controller.nSelect);
    data |= @as(u16, controller.nL3    ) <<  1;
    data |= @as(u16, controller.nR3    ) <<  2;
    data |= @as(u16, controller.nStart ) <<  3;
    data |= @as(u16, controller.nUp    ) <<  4;
    data |= @as(u16, controller.nRight ) <<  5;
    data |= @as(u16, controller.nDown  ) <<  6;
    data |= @as(u16, controller.nLeft  ) <<  7;
    data |= @as(u16, controller.nL2    ) <<  8;
    data |= @as(u16, controller.nR2    ) <<  9;
    data |= @as(u16, controller.nL1    ) << 10;
    data |= @as(u16, controller.nR1    ) << 11;
    data |= @as(u16, controller.nTri   ) << 12;
    data |= @as(u16, controller.nCircle) << 13;
    data |= @as(u16, controller.nCross ) << 14;
    data |= @as(u16, controller.nSquare) << 15;

    return data;
}
