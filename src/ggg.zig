//! Common data types used by GDEF/GPOS/GSUB tables.
//!
//! <https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2>

// A heavily modified port of https://github.com/harfbuzz/rustybuzz implementation
// originally written by https://github.com/laurmaedje

// internal reëxports
const layout_table = @import("ggg/layout_table.zig");
pub const LayoutTable = layout_table.LayoutTable;

// end of internal reëxports

const parser = @import("parser.zig");

const GlyphId = @import("lib.zig").GlyphId;
const LazyArray16 = parser.LazyArray16;

/// A [Class Definition Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#class-definition-table).
pub const ClassDefinition = union(enum) {
    format1: struct { start: GlyphId, classes: LazyArray16(Class) },
    format2: struct { records: LazyArray16(RangeRecord) },
    empty,
};

/// A value of [Class Definition Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#class-definition-table).
pub const Class = u16;

/// A record that describes a range of glyph IDs.
pub const RangeRecord = struct {
    /// First glyph ID in the range
    start: GlyphId,
    /// Last glyph ID in the range
    end: GlyphId,
    /// Coverage Index of first glyph ID in range.
    value: u16,
};

/// A [Coverage Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#coverage-table).
pub const Coverage = union(enum) {
    format1: struct {
        /// Array of glyph IDs. Sorted.
        glyphs: LazyArray16(GlyphId),
    },
    format2: struct {
        /// Array of glyph ranges. Ordered by `RangeRecord.start`.
        records: LazyArray16(RangeRecord),
    },
};
