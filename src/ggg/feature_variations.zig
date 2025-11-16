const parser = @import("../parser.zig");

const LookupList = @import("lookup.zig").LookupList;

const LazyArray32 = parser.LazyArray32;
const Offset32 = parser.Offset32;

/// A [Feature Variations Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#featurevariations-table).
pub const FeatureVariations = struct {
    data: []const u8,
    records: LazyArray32(FeatureVariationRecord),
};

const FeatureVariationRecord = struct {
    conditions: Offset32,
    substitutions: Offset32,
};
