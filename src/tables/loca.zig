//! An [Index to Location Table](https://docs.microsoft.com/en-us/typography/opentype/spec/loca)
//! implementation.

const std = @import("std");
const lib = @import("../lib.zig");
const parser = @import("../parser.zig");

/// An [Index to Location Table](https://docs.microsoft.com/en-us/typography/opentype/spec/loca).
pub const Table = union(enum) {
    /// Short offsets.
    short: parser.LazyArray16(u16),
    /// Long offsets.
    long: parser.LazyArray16(u32),

    /// Parses a table from raw data.
    ///
    /// - `number_of_glyphs` is from the `maxp` table.
    /// - `format` is from the `head` table.
    pub fn parse(
        number_of_glyphs: u16, // non zero
        format: @import("head.zig").IndexToLocationFormat,
        data: []const u8,
    ) parser.Error!Table {
        // The number of ranges is `maxp.numGlyphs + 1`.
        //
        // [ARs] Consider overflow first.
        var total = number_of_glyphs +| 1;

        // By the spec, the number of `loca` offsets is `maxp.numGlyphs + 1`.
        // But some malformed fonts can have less glyphs than that.
        // In which case we try to parse only the available offsets
        // and do not return an error, since the expected data length
        // would go beyond table's length.
        //
        // In case when `loca` has more data than needed we simply ignore the rest.
        const actual_total = std.math.cast(u16, switch (format) {
            .short => data.len / 2,
            .long => data.len / 4,
        }) orelse return error.ParseFail;

        total = @min(actual_total, total);
        var s = parser.Stream.new(data);

        return switch (format) {
            .short => .{ .short = try s.read_array(u16, total) },
            .long => .{ .long = try s.read_array(u32, total) },
        };
    }

    /// Returns the number of offsets.
    pub fn len(
        self: Table,
    ) u16 {
        return switch (self) {
            inline else => |array| array.len(),
        };
    }

    /// Returns glyph's range in the `glyf` table.
    pub fn glyph_range(
        self: Table,
        glyph_id: lib.GlyphId,
    ) ?struct { usize, usize } {
        const id = glyph_id[0];
        if (id == std.math.maxInt(u16)) return null;

        // Glyph ID must be smaller than total number of values in a `loca` array.
        if (id + 1 >= self.len()) return null;

        const start: usize, const end: usize = switch (self) {
            .short => |array| .{
                // 'The actual local offset divided by 2 is stored.'
                @as(usize, array.get(id) orelse return null) * 2,
                @as(usize, array.get(id + 1) orelse return null) * 2,
            },
            .long => |array| .{
                @as(usize, array.get(id) orelse return null),
                @as(usize, array.get(id + 1) orelse return null),
            },
        };

        return if (start >= end)
            // 'The offsets must be in ascending order.'
            // And range cannot be empty.
            null
        else
            .{ start, end };
    }
};
