//! An [Index to Location Table](https://docs.microsoft.com/en-us/typography/opentype/spec/loca)
//! implementation.

const std = @import("std");
const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;

/// An [Index to Location Table](https://docs.microsoft.com/en-us/typography/opentype/spec/loca).
pub const Table = union(enum) {
    /// Short offsets.
    short: LazyArray16(u16),
    /// Long offsets.
    long: LazyArray16(u32),

    /// Parses a table from raw data.
    ///
    /// - `number_of_glyphs` is from the `maxp` table.
    /// - `format` is from the `head` table.
    pub fn parse(
        number_of_glyphs: u16, // non zero
        format: @import("head.zig").IndexToLocationFormat,
        data: []const u8,
    ) ?Table {
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
        }) orelse return null;

        total = @min(actual_total, total);
        var s = parser.Stream.new(data);

        return switch (format) {
            .short => .{ .short = s.read_array(u16, total) orelse return null },
            .long => .{ .long = s.read_array(u32, total) orelse return null },
        };
    }
};
