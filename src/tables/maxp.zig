//! A [Maximum Profile Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/maxp) implementation.

const parser = @import("../parser.zig");

/// A [Maximum Profile Table](https://docs.microsoft.com/en-us/typography/opentype/spec/maxp).
pub const Table = struct {
    /// The total number of glyphs in the face.
    number_of_glyphs: u16, // nonzero,

    /// Parses a table from raw data.
    pub fn parse(data: []const u8) ?Table {
        var s = parser.Stream.new(data);
        const version = s.read(u32) orelse return null;
        if (!(version == 0x00005000 or version == 0x00010000)) {
            return null;
        }

        const n = s.read(u16) orelse return null;
        if (n == 0) return null;

        return .{ .number_of_glyphs = n };
    }
};
