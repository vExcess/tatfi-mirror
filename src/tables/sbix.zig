//! A [Standard Bitmap Graphics Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/sbix) implementation.

const parser = @import("../parser.zig");

const LazyArray32 = parser.LazyArray32;
const Offset32 = parser.Offset32;

/// A [Standard Bitmap Graphics Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/sbix).
pub const Table = struct {
    /// A list of [`Strike`]s.
    strikes: Strikes,
};

/// A list of [`Strike`]s.
pub const Strikes = struct {
    /// `sbix` table data.
    data: []const u8,
    // Offsets from the beginning of the `sbix` table.
    offsets: LazyArray32(Offset32),
    // The total number of glyphs in the face + 1. From the `maxp` table.
    number_of_glyphs: u16,
};
