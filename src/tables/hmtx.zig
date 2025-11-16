//! A [Horizontal/Vertical Metrics Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;

/// A [Horizontal/Vertical Metrics Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx).
///
/// `hmtx` and `vmtx` tables has the same structure, so we're reusing the same struct for both.
pub const Table = struct {
    /// A list of metrics indexed by glyph ID.
    metrics: LazyArray16(Metrics),
    /// Side bearings for glyph IDs greater than or equal to the number of `metrics` values.
    bearings: LazyArray16(i16),
    /// Sum of long metrics + bearings.
    number_of_metrics: u16,
};

/// Horizontal/Vertical Metrics.
pub const Metrics = struct {
    /// Width/Height advance for `hmtx`/`vmtx`.
    advance: u16,
    /// Left/Top side bearing for `hmtx`/`vmtx`.
    side_bearing: i16,
};
