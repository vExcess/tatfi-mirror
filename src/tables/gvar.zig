//! A [Glyph Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/gvar) implementation.

// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#tuple-variation-store

const std = @import("std");
const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;
const F2DOT14 = parser.F2DOT14;

/// A [Glyph Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/gvar).
pub const Table = struct {
    axis_count: u16, // nonzero
    shared_tuple_records: LazyArray16(F2DOT14),
    offsets: GlyphVariationDataOffsets,
    glyphs_variation_data: []const u8,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        const axis_count = try s.read(u16);

        // The axis count cannot be zero.
        if (axis_count == 0) return error.ParseFail;

        const shared_tuple_count = try s.read(u16);
        const shared_tuples_offset = try s.read(Offset32);
        const glyph_count = try s.read(u16);
        const flags = try s.read(u16);

        const glyph_variation_data_array_offset = try s.read(Offset32);
        if (glyph_variation_data_array_offset[0] > data.len) return error.ParseFail;

        const shared_tuple_records = str: {
            var sub_s = try parser.Stream.new_at(data, shared_tuples_offset[0]);
            const count = try std.math.mul(u16, shared_tuple_count, axis_count);
            break :str try sub_s.read_array(F2DOT14, count);
        };

        const glyphs_variation_data = data[glyph_variation_data_array_offset[0]..];

        const offsets: GlyphVariationDataOffsets = o: {
            const offsets_count = try std.math.add(u16, glyph_count, 1);
            const is_long_format = flags & 1 == 1; // The first bit indicates a long format.
            break :o if (is_long_format)
                .{ .long = try s.read_array(Offset32, offsets_count) }
            else
                .{ .short = try s.read_array(Offset16, offsets_count) };
        };

        return .{
            .axis_count = axis_count,
            .shared_tuple_records = shared_tuple_records,
            .offsets = offsets,
            .glyphs_variation_data = glyphs_variation_data,
        };
    }
};

const GlyphVariationDataOffsets = union(enum) {
    short: LazyArray16(Offset16),
    long: LazyArray16(Offset32),
};
