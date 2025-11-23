//! An [Extended Kerning Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6kerx.html) implementation.

// [RazrFalcon]
// TODO: find a way to test this table
// This table is basically untested because it uses Apple's State Tables
// and I have no idea how to generate them.

const parser = @import("../parser.zig");

/// An [Extended Kerning Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6kerx.html).
pub const Table = struct {
    /// A list of subtables.
    subtables: Subtables,

    /// Parses a table from raw data.
    ///
    /// `number_of_glyphs` is from the `maxp` table.
    pub fn parse(
        number_of_glyphs: u16,
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        s.skip(u16); // version
        s.skip(u16); // padding
        const number_of_tables = try s.read(u32);

        return .{
            .subtables = .{
                .number_of_glyphs = number_of_glyphs,
                .number_of_tables = number_of_tables,
                .data = try s.tail(),
            },
        };
    }
};

/// A list of extended kerning subtables.
///
/// The internal data layout is not designed for random access,
/// therefore we're not providing the `get()` method and only an iterator.
pub const Subtables = struct {
    /// The number of glyphs from the `maxp` table.
    number_of_glyphs: u16, // nonzero
    /// The total number of tables.
    number_of_tables: u32,
    /// Actual data. Starts right after the `kerx` header.
    data: []const u8,
};
