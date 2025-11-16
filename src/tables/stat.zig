//! A [Style Attributes Table](https://docs.microsoft.com/en-us/typography/opentype/spec/stat) implementation.

const parser = @import("../parser.zig");

const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;

/// A [Style Attributes Table](https://docs.microsoft.com/en-us/typography/opentype/spec/stat).
pub const Table = struct {
    /// List of axes
    axes: LazyArray16(AxisRecord),
    /// Fallback name when everything can be elided.
    fallback_name_id: ?u16,
    version: u32,
    data: []const u8,
    value_lookup_start: Offset32,
    value_offsets: LazyArray16(Offset16),
};

/// The [axis record](https://learn.microsoft.com/en-us/typography/opentype/spec/stat#axis-records) struct provides information about a single design axis.
pub const AxisRecord = struct {
    /// Axis tag.
    tag: Tag,
    /// The name ID for entries in the 'name' table that provide a display string for this axis.
    name_id: u16,
    /// Sort order for e.g. composing font family or face names.
    ordering: u16,
};
