//! A collection of [Apple Advanced Typography](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6AATIntro.html)
//! related types.

const std = @import("std");
const parser = @import("parser.zig");
const lib = @import("lib.zig");

const LazyArray16 = parser.LazyArray16;

/// A [lookup table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6Tables.html).
///
/// u32 values in Format10 tables will be truncated to u16.
/// u64 values in Format10 tables are not supported.
pub const Lookup = struct {
    data: LookupInner,

    /// Parses a lookup table from raw data.
    ///
    /// `number_of_glyphs` is from the `maxp` table.
    pub fn parse(
        number_of_glyphs: u16,
        data: []const u8,
    ) parser.Error!Lookup {
        return .{
            .data = try .parse(number_of_glyphs, data),
        };
    }
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

    fn parse(
        number_of_glyphs: u16,
        data: []const u8,
    ) parser.Error!LookupInner {
        var s = parser.Stream.new(data);
        const format = try s.read(u16);

        switch (format) {
            0 => {
                const values = try s.read_array(u16, number_of_glyphs);
                return .{ .format1 = values };
            },
            2 => {
                const bsearch: BinarySearchTable(LookupSegment) = try .parse(try s.tail());
                return .{ .format2 = bsearch };
            },
            4 => {
                const bsearch: BinarySearchTable(LookupSegment) = try .parse(try s.tail());
                return .{ .format4 = .{ bsearch, data } };
            },
            6 => {
                const bsearch: BinarySearchTable(LookupSingle) = try .parse(try s.tail());
                return .{ .format6 = bsearch };
            },
            8 => {
                const first_glyph = try s.read(u16);
                const glyph_count = try s.read(u16);
                const values = try s.read_array(u16, glyph_count);
                return .{ .format8 = .{
                    .first_glyph = first_glyph,
                    .values = values,
                } };
            },
            10 => {
                const value_size = try s.read(u16);
                const first_glyph = try s.read(u16);
                const glyph_count = try s.read(u16);
                return .{ .format10 = .{
                    .value_size = value_size,
                    .first_glyph = first_glyph,
                    .glyph_count = glyph_count,
                    .data = try s.tail(),
                } };
            },
            else => return error.ParseFail,
        }
    }
};

/// A binary searching table as defined at
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6Tables.html
fn BinarySearchTable(T: type) type {
    return struct {
        values: LazyArray16(T),
        len: u16, // NonZeroU16, // values length excluding termination segment

        const Self = @This();

        fn parse(
            data: []const u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            const segment_size = try s.read(u16);
            const number_of_segments = try s.read(u16);
            s.advance(6); // search_range + entry_selector + range_shift

            if (segment_size != T.FromData.SIZE) return error.ParseFail;
            if (number_of_segments == 0) return error.ParseFail;

            const values = try s.read_array(T, number_of_segments);

            // 'The number of termination values that need to be included is table-specific.
            // The value that indicates binary search termination is 0xFFFF.'
            const last_value = values.last() orelse return error.ParseFail;
            const len = if (T.FromData.is_termination(last_value))
                try std.math.sub(u16, number_of_segments, 1)
            else
                number_of_segments;
            if (len == 0) return error.ParseFail;

            return .{
                .len = len,
                .values = values,
            };
        }
    };
}

pub const LookupSegment = struct {
    last_glyph: u16,
    first_glyph: u16,
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
                .last_glyph = try s.read(u16),
                .first_glyph = try s.read(u16),
                .value = try s.read(u16),
            };
        }

        // for trait BinarySearchValue:FromData
        fn is_termination(
            self: Self,
        ) bool {
            return self.last_glyph == 0xFFFF and self.first_glyph == 0xFFFF;
        }
    };
};

pub const LookupSingle = struct {
    glyph: u16,
    value: u16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph = try s.read(u16),
                .value = try s.read(u16),
            };
        }

        // for trait BinarySearchValue:FromData
        fn is_termination(
            self: Self,
        ) bool {
            return self.glyph == 0xFFFF;
        }
    };
};

/// A [State Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6Tables.html).
///
/// Also called `STHeader`.
///
/// Currently used by `kern` table.
pub const StateTable = struct {
    number_of_classes: u16,
    first_glyph: lib.GlyphId,
    class_table: []const u8,
    state_array_offset: u16,
    state_array: []const u8,
    entry_table: []const u8,
    actions: []const u8,

    pub fn parse(
        data: []const u8,
    ) parser.Error!StateTable {
        var s = parser.Stream.new(data);

        const number_of_classes = try s.read(u16);
        // Note that in format1 subtable, offsets are not from the subtable start,
        // but from subtable start + `header_size`.
        // So there is not need to subtract the `header_size`.
        const class_table_offset: usize = (try s.read(parser.Offset16))[0];
        const state_array_offset: usize = (try s.read(parser.Offset16))[0];
        const entry_table_offset: usize = (try s.read(parser.Offset16))[0];
        // Ignore `values_offset` since we don't use it.

        // Parse class subtable.
        s.offset = class_table_offset;
        const first_glyph = try s.read(lib.GlyphId);
        const number_of_glyphs = try s.read(u16);
        // The class table contains u8, so it's easier to use just a slice
        // instead of a LazyArray.
        const class_table = try s.read_bytes(number_of_glyphs);

        if (state_array_offset > data.len or
            entry_table_offset > data.len) return error.ParseFail;

        return .{
            .number_of_classes = number_of_classes,
            .first_glyph = first_glyph,
            .class_table = class_table,
            .state_array_offset = @truncate(state_array_offset),
            // We don't know the actual data size and it's kinda expensive to calculate.
            // So we are simply storing all the data past the offset.
            // Despite the fact that they may overlap.
            .state_array = data[state_array_offset..],
            .entry_table = data[entry_table_offset..],
            // `ValueOffset` defines an offset from the start of the subtable data.
            // We do not check that the provided offset is actually after `values_offset`.
            .actions = data,
        };
    }
};
