//! A [Vertical Origin Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/vorg) implementation.

const parser = @import("../parser.zig");

const GlyphId = @import("../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;

/// A [Vertical Origin Table](https://docs.microsoft.com/en-us/typography/opentype/spec/vorg).
pub const Table = struct {
    /// Default origin.
    default_y: i16,
    /// A list of metrics for each glyph.
    ///
    /// Ordered by `glyph_id`.
    metrics: LazyArray16(VerticalOriginMetrics),
};

/// Vertical origin metrics for the
/// [Vertical Origin Table](https://docs.microsoft.com/en-us/typography/opentype/spec/vorg).
pub const VerticalOriginMetrics = struct {
    /// Glyph ID.
    glyph_id: GlyphId,
    /// Y coordinate, in the font's design coordinate system, of the vertical origin.
    y: i16,
};
