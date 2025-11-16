//! A [Maximum Profile Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/maxp) implementation.

/// A [Maximum Profile Table](https://docs.microsoft.com/en-us/typography/opentype/spec/maxp).
pub const Table = struct {
    /// The total number of glyphs in the face.
    number_of_glyphs: u16, // nonzero,
};
