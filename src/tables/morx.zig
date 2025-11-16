//! An [Extended Glyph Metamorphosis Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6morx.html) implementation.

// [RazrFalcon]
// Note: We do not have tests for this table because it has a very complicated structure.
// Specifically, the State Machine Tables. I have no idea how to generate them.
// And all fonts that use this table are mainly Apple one, so we cannot use them for legal reasons.
//
// On the other hand, this table is tested indirectly by https://github.com/harfbuzz/rustybuzz
// And it has like 170 tests. Which is pretty good.
// Therefore after applying any changes to this table,
// you have to check that all rustybuzz tests are still passing.

const cfg = @import("config");

/// An [Extended Glyph Metamorphosis Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6morx.html).
///
/// Subtable Glyph Coverage used by morx v3 is not supported.
pub const Table = struct {
    /// A list of metamorphosis chains.
    chains: Chains,
};

/// A list of metamorphosis chains.
///
/// The internal data layout is not designed for random access,
/// therefore we're not providing the `get()` method and only an iterator.
pub const Chains = struct {
    data: []const u8,
    count: u32,
    number_of_glyphs: u16, // nonzero
};
