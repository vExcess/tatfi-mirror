const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const LazyOffsetArray16 = parser.LazyOffsetArray16;
const Offset16 = parser.Offset16;

/// A list of [`Lookup`] values.
pub const LookupList = LazyOffsetArray16(Lookup);

/// A [Lookup Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#lookup-table).
pub const Lookup = struct {
    /// Lookup qualifiers.
    flags: LookupFlags,
    /// Available subtables.
    subtables: LookupSubtables,
    /// Index into GDEF mark glyph sets structure.
    mark_filtering_set: ?u16,
};

/// Lookup table flags.
pub const LookupFlags = struct { u16 };

/// A list of lookup subtables.
pub const LookupSubtables = struct {
    kind: u16,
    data: []const u8,
    offsets: LazyArray16(Offset16),
};
