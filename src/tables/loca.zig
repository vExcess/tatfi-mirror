//! An [Index to Location Table](https://docs.microsoft.com/en-us/typography/opentype/spec/loca)
//! implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;

/// An [Index to Location Table](https://docs.microsoft.com/en-us/typography/opentype/spec/loca).
pub const Table = union(enum) {
    /// Short offsets.
    short: LazyArray16(u16),
    /// Long offsets.
    long: LazyArray16(u32),
};
