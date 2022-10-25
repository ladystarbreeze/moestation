//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! cop0.zig - IOP COP0
//!

const std = @import("std");

const assert = std.debug.assert;

const err  = std.log.err;
const info = std.log.info;

const Cop0Reg = @import("cop0.zig").Cop0Reg;

/// Returns a COP0 register
pub fn get(idx: u5) u32 {
    var data: u32 = undefined;

    switch (idx) {
        @enumToInt(Cop0Reg.PRId ) => data = 2,
        else => {
            err("  [COP0 (IOP)] Unhandled register read @ {s}.", .{@tagName(@intToEnum(Cop0Reg, idx))});

            assert(false);
        }
    }

    return data;
}
