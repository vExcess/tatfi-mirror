//! A [Standard Bitmap Graphics Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/sbix) implementation.

const std = @import("std");
const parser = @import("../parser.zig");

const LazyArray32 = parser.LazyArray32;
const Offset32 = parser.Offset32;

/// A [Standard Bitmap Graphics Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/sbix).
pub const Table = struct {
    /// A list of [`Strike`]s.
    strikes: Strikes,

    /// Parses a table from raw data.
    ///
    /// - `number_of_glyphs` is from the `maxp` table.
    pub fn parse(
        number_of_glyphs: u16,
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u16);
        if (version != 1) return error.ParseFail;

        s.skip(u16); // flags

        const strikes_count = try s.read(u32);
        if (strikes_count == 0) return error.ParseFail;

        const offsets = try s.read_array(Offset32, strikes_count);

        return .{ .strikes = .{
            .data = data,
            .offsets = offsets,
            .number_of_glyphs = number_of_glyphs +| 1,
        } };
    }
};

/// A list of [`Strike`]s.
pub const Strikes = struct {
    /// `sbix` table data.
    data: []const u8,
    // Offsets from the beginning of the `sbix` table.
    offsets: LazyArray32(Offset32),
    // The total number of glyphs in the face + 1. From the `maxp` table.
    number_of_glyphs: u16,
};
