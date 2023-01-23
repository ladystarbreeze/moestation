//!
//! moestation - PlayStation 2 emulator written in Zig.
//! Copyright (c) 2022 Michelle-Marie Schiller
//!
//! min_max.zig
//!

const std = @import("std");

const assert = std.debug.assert;

const isNumber = std.meta.trait.isNumber;

/// Returns the bigger number
pub fn max(comptime T: type, a: T, b: T) T {
    assert(isNumber(T));

    return if (a > b) a else b;
}

/// Returns the smaller number
pub fn min(comptime T: type, a: T, b: T) T {
    assert(isNumber(T));

    return if (a < b) a else b;
}
