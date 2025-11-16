//! A [Color Palette Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cpal) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;

/// A [Color Palette Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cpal).
pub const Table = struct {
    color_indices: LazyArray16(u16),
    colors: LazyArray16(BgraColor),
};
const BgraColor = struct { blue: u8, green: u8, red: u8, alpha: u8 };
