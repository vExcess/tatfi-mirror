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

    pub fn parse(
        data: []const u8,
    ) parser.Error!ClassDefinition {
        var s = parser.Stream.new(data);
        const v = try s.read(u16);

        switch (v) {
            1 => {
                const start = try s.read(GlyphId);
                const count = try s.read(u16);
                const classes = try s.read_array(Class, count);
                return .{ .format1 = .{
                    .start = start,
                    .classes = classes,
                } };
            },
            2 => {
                const count = try s.read(u16);
                const records = try s.read_array(RangeRecord, count);
                return .{ .format2 = .{ .records = records } };
            },
            else => return error.ParseFail,
        }
    }
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

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 6;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .start = try s.read(GlyphId),
                .end = try s.read(GlyphId),
                .value = try s.read(u16),
            };
        }
    };
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

    pub fn parse(
        data: []const u8,
    ) parser.Error!Coverage {
        var s = parser.Stream.new(data);
        switch (try s.read(u16)) {
            1 => {
                const count = try s.read(u16);
                const glyphs = try s.read_array(GlyphId, count);
                return .{ .format1 = .{ .glyphs = glyphs } };
            },
            2 => {
                const count = try s.read(u16);
                const records = try s.read_array(RangeRecord, count);
                return .{ .format2 = .{ .records = records } };
            },
            else => return error.ParseFail,
        }
    }
};
