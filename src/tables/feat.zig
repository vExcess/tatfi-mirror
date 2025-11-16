//! A [Feature Name Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6feat.html) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

/// A [Feature Name Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6feat.html).
pub const Table = struct {
    /// A list of feature names. Sorted by `FeatureName.feature`.
    names: FeatureNames,
};

/// A list of feature names.
pub const FeatureNames = struct {
    data: []const u8,
    records: LazyArray16(FeatureNameRecord),
};

const FeatureNameRecord = struct {
    feature: u16,
    setting_table_records_count: u16,
    // Offset from the beginning of the table.
    setting_table_offset: Offset32,
    flags: u8,
    default_setting_index: u8,
    name_index: u16,
};
