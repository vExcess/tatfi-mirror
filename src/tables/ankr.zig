//! An [Anchor Point Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6ankr.html) implementation.

const aat = @import("../aat.zig");
const parser = @import("../parser.zig");

const Offset32 = parser.Offset32;

/// An [Anchor Point Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6ankr.html).
pub const Table = struct {
    lookup: aat.Lookup,
    // Ideally, Glyphs Data can be represented as an array,
    // but Apple's spec doesn't specify that Glyphs Data members have padding or not.
    // Meaning we cannot simply iterate over them.
    glyphs_data: []const u8,

    /// Parses a table from raw data.
    ///
    /// `number_of_glyphs` is from the `maxp` table.
    pub fn parse(
        number_of_glyphs: u16,
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        if (try s.read(u16) != 0) return error.ParseFail; // version
        s.skip(u16); // reserved

        // TODO: we should probably check that offset is larger than the header size (8)
        const lookup_table = r: {
            const offset = (try s.read(Offset32))[0];
            if (offset > data.len) return error.ParseFail;
            break :r data[offset..];
        };
        const glyphs_data = r: {
            const offset = (try s.read(Offset32))[0];
            if (offset > data.len) return error.ParseFail;
            break :r data[offset..];
        };

        return .{
            .lookup = try .parse(number_of_glyphs, lookup_table),
            .glyphs_data = glyphs_data,
        };
    }
};
