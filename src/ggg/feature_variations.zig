const parser = @import("../parser.zig");

const LookupList = @import("lookup.zig").LookupList;

const LazyArray32 = parser.LazyArray32;
const Offset32 = parser.Offset32;

/// A [Feature Variations Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#featurevariations-table).
pub const FeatureVariations = struct {
    data: []const u8,
    records: LazyArray32(FeatureVariationRecord),

    pub fn parse(
        data: []const u8,
    ) parser.Error!FeatureVariations {
        var s = parser.Stream.new(data);
        if (try s.read(u16) != 1) return error.ParseFail; // major version
        s.skip(u16); // minor version

        const count = try s.read(u32);
        const records = try s.read_array(FeatureVariationRecord, count);

        return .{
            .data = data,
            .records = records,
        };
    }
};

const FeatureVariationRecord = struct {
    conditions: Offset32,
    substitutions: Offset32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 8;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            return try parser.parse_struct_from_data(Self, data);
        }
    };
};
