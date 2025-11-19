//! A [Vertical Header Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/vhea) implementation.

const parser = @import("../parser.zig");

/// A [Vertical Header Table](https://docs.microsoft.com/en-us/typography/opentype/spec/vhea).
pub const Table = struct {
    /// Face ascender.
    ascender: i16,
    /// Face descender.
    descender: i16,
    /// Face line gap.
    line_gap: i16,
    /// Number of metrics in the `vmtx` table.
    number_of_metrics: u16,

    /// Parses a table from raw data.
    pub fn parse(data: []const u8) ?Table {
        // Do not check the exact length, because some fonts include
        // padding in table's length in table records, which is incorrect.
        if (data.len < 36) return null;

        var s = parser.Stream.new(data);
        s.skip(u32); // version
        const ascender = s.read(i16) orelse return null;
        const descender = s.read(i16) orelse return null;
        const line_gap = s.read(i16) orelse return null;
        s.advance(24);
        const number_of_metrics = s.read(u16) orelse return null;

        return .{
            .ascender = ascender,
            .descender = descender,
            .line_gap = line_gap,
            .number_of_metrics = number_of_metrics,
        };
    }
};
