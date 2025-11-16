//! A [PostScript Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/post) implementation.

const parser = @import("../parser.zig");

const LineMetrics = @import("../lib.zig").LineMetrics;

const LazyArray16 = parser.LazyArray16;

/// A [PostScript Table](https://docs.microsoft.com/en-us/typography/opentype/spec/post).
pub const Table = struct {
    /// Italic angle in counter-clockwise degrees from the vertical.
    italic_angle: f32,
    /// Underline metrics.
    underline_metrics: LineMetrics,
    /// Flag that indicates that the font is monospaced.
    is_monospaced: bool,
    glyph_indexes: LazyArray16(u16),
    names_data: []const u8,
};
