//! An [Extended Kerning Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6kerx.html) implementation.

// [RazrFalcon]
// TODO: find a way to test this table
// This table is basically untested because it uses Apple's State Tables
// and I have no idea how to generate them.

/// An [Extended Kerning Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6kerx.html).
pub const Table = struct {
    /// A list of subtables.
    subtables: Subtables,
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
