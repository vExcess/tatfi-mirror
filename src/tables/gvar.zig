//! A [Glyph Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/gvar) implementation.

// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#tuple-variation-store

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;
const F2DOT14 = parser.F2DOT14;

/// A [Glyph Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/gvar).
pub const Table = struct {
    axis_count: u16, // nonzero
    shared_tuple_records: LazyArray16(F2DOT14),
    offsets: GlyphVariationDataOffsets,
    glyphs_variation_data: []const u8,
};

const GlyphVariationDataOffsets = union(enum) {
    short: LazyArray16(Offset16),
    long: LazyArray16(Offset32),
};
