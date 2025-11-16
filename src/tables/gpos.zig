//! A [Glyph Positioning Table](https://docs.microsoft.com/en-us/typography/opentype/spec/gpos)
//! implementation.

// A heavily modified port of https://github.com/harfbuzz/rustybuzz implementation
// originally written by https://github.com/laurmaedje

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;

/// A [Device Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#devVarIdxTbls).
pub const Device = union(enum) {
    hinting: HintingDevice,
    variation: VariationDevice,
};

/// A [Device Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#devVarIdxTbls)
/// hinting values.
pub const HintingDevice = struct {
    start_size: u16,
    end_size: u16,
    delta_format: u16,
    delta_values: LazyArray16(u16),
};

/// A [Device Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#devVarIdxTbls)
/// indexes into [Item Variation Store](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#IVS).
pub const VariationDevice = struct {
    outer_index: u16,
    inner_index: u16,
};
