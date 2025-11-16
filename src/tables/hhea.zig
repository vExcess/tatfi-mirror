//! A [Horizontal Header Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/hhea) implementation.

const parser = @import("../parser.zig");

/// A [Horizontal Header Table](https://docs.microsoft.com/en-us/typography/opentype/spec/hhea).
pub const Table = struct {
    /// Face ascender.
    ascender: i16,
    /// Face descender.
    descender: i16,
    /// Face line gap.
    line_gap: i16,
    /// Number of metrics in the `hmtx` table.
    number_of_metrics: u16,
};
