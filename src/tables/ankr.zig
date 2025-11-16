//! An [Anchor Point Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6ankr.html) implementation.

const aat = @import("../aat.zig");

/// An [Anchor Point Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6ankr.html).
pub const Table = struct {
    lookup: aat.Lookup,
    // Ideally, Glyphs Data can be represented as an array,
    // but Apple's spec doesn't specify that Glyphs Data members have padding or not.
    // Meaning we cannot simply iterate over them.
    glyphs_data: []const u8,
};
