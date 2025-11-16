//! A [Font Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/fvar) implementation.

const parser = @import("../parser.zig");

const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

/// A [Font Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/fvar).
pub const Table = struct {
    /// A list of variation axes.
    axes: LazyArray16(VariationAxis),
};

/// A [variation axis](https://docs.microsoft.com/en-us/typography/opentype/spec/fvar#variationaxisrecord).
pub const VariationAxis = struct {
    tag: Tag,
    min_value: f32,
    def_value: f32,
    max_value: f32,
    /// An axis name in the `name` table.
    name_id: u16,
    hidden: bool,
};
