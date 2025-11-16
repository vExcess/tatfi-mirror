//!
//! A [Kerning Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/kern) implementation.
//!
//! Supports both
//! [OpenType](https://docs.microsoft.com/en-us/typography/opentype/spec/kern)
//! and
//! [Apple Advanced Typography](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6kern.html)
//! variants.
//!
//! Since there is no single correct way to process a kerning data,
//! we have to provide an access to kerning subtables, so a caller can implement
//! a kerning algorithm manually.
//! But we still try to keep the API as high-level as possible.

const GlyphId = @import("../lib.zig").GlyphId;

/// A [Kerning Table](https://docs.microsoft.com/en-us/typography/opentype/spec/kern).
pub const Table = struct {
    /// A list of subtables.
    subtables: Subtables,
};

/// A list of subtables.
///
/// The internal data layout is not designed for random access,
/// therefore we're not providing the `get()` method and only an iterator.
pub const Subtables = struct {
    /// Indicates an Apple Advanced Typography format.
    is_aat: bool,
    /// The total number of tables.
    count: u32,
    /// Actual data. Starts right after the `kern` header.
    data: []const u8,
};
