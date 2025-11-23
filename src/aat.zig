//! A collection of [Apple Advanced Typography](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6AATIntro.html)
//! related types.

const std = @import("std");
const parser = @import("parser.zig");

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
