//! A [Font Header Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/head) implementation.

const Rect = @import("../lib.zig").Rect;

/// A [Font Header Table](https://docs.microsoft.com/en-us/typography/opentype/spec/head).
pub const Table = struct {
    /// Units per EM.
    ///
    /// Guarantee to be in a 16..=16384 range.
    units_per_em: u16,
    /// A bounding box that large enough to enclose any glyph from the face.
    global_bbox: Rect,
    /// An index format used by the [Index to Location Table](
    /// https://docs.microsoft.com/en-us/typography/opentype/spec/loca).
    index_to_location_format: IndexToLocationFormat,
};

/// An index format used by the [Index to Location Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/loca).
pub const IndexToLocationFormat = enum { short, long };
