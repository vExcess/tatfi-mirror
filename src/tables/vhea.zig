//! A [Vertical Header Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/vhea) implementation.

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
};
