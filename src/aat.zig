//! A collection of [Apple Advanced Typography](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6AATIntro.html)
//! related types.

const parser = @import("parser.zig");

const LazyArray16 = parser.LazyArray16;

/// A [lookup table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6Tables.html).
///
/// u32 values in Format10 tables will be truncated to u16.
/// u64 values in Format10 tables are not supported.
pub const Lookup = struct {
    data: LookupInner,
};

const LookupInner = union(enum) {
    format1: LazyArray16(u16),
    format2: BinarySearchTable(LookupSegment),
    format4: struct { BinarySearchTable(LookupSegment), []const u8 },
    format6: BinarySearchTable(LookupSingle),
    format8: struct { first_glyph: u16, values: LazyArray16(u16) },
    format10: struct {
        value_size: u16,
        first_glyph: u16,
        glyph_count: u16,
        data: []const u8,
    },
};

/// A binary searching table as defined at
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6Tables.html
fn BinarySearchTable(T: type) type {
    return struct {
        values: LazyArray16(T),
        len: u16, // NonZeroU16, // values length excluding termination segment
    };
}

pub const LookupSegment = struct {
    last_glyph: u16,
    first_glyph: u16,
    value: u16,
};

pub const LookupSingle = struct {
    glyph: u16,
    value: u16,
};
