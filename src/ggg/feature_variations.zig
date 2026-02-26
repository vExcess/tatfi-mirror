const lib = @import("../lib.zig");
const parser = @import("../parser.zig");
const utils = @import("../utils.zig");

pub const VariationIndex = lib.opentype_layout.VariationIndex;
const LookupList = @import("lookup.zig").LookupList;

/// A [Feature Variations Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#featurevariations-table).
const FeatureVariations = @This();

data: []const u8,
records: parser.LazyArray32(FeatureVariationRecord),

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

/// Returns a []const VariationIndex for variation coordinates.
pub fn find_index(
    self: *const FeatureVariations,
    coords: []const lib.NormalizedCoordinate,
) ?VariationIndex {
    var i: VariationIndex = 0;
    while (i < self.records.len()) : (i += 1) {
        const record = self.records.get(i) orelse return null;
        const offset: usize = record.conditions[0];

        const data = utils.slice(self.data, offset) catch return null;
        const set = ConditionSet.parse(data) catch return null;

        if (set.evaluate(coords))
            return i;
    }

    return null;
}

const ConditionSet = struct {
    data: []const u8,
    conditions: parser.LazyArray16(parser.Offset32),

    fn parse(
        data: []const u8,
    ) parser.Error!ConditionSet {
        var s = parser.Stream.new(data);
        const count = try s.read(u16);

        const conditions = try s.read_array(parser.Offset32, count);
        return .{
            .data = data,
            .conditions = conditions,
        };
    }

    fn evaluate(
        self: ConditionSet,
        coords: []const lib.NormalizedCoordinate,
    ) bool {
        var iter = self.conditions.iterator();
        return while (iter.next()) |offset| {
            const data = utils.slice(self.data, offset[0]) catch break false;
            const c = Condition.parse(data) catch break false;

            if (!c.evaluate(coords)) break false;
        } else true;
    }
};

const Condition = union(enum) {
    format1: struct {
        axis_index: u16,
        filter_range_min: i16,
        filter_range_max: i16,
    },

    fn parse(
        data: []const u8,
    ) parser.Error!Condition {
        var s = parser.Stream.new(data);
        const format = try s.read(u16);

        return switch (format) {
            1 => .{ .format1 = .{
                .axis_index = try s.read(u16),
                .filter_range_min = try s.read(i16),
                .filter_range_max = try s.read(i16),
            } },
            else => error.ParseFail,
        };
    }

    fn evaluate(
        self: Condition,
        coords: []const lib.NormalizedCoordinate,
    ) bool {
        const coord: i16 = c: {
            const axis_index = self.format1.axis_index;
            if (axis_index >= coords.len) break :c 0;
            break :c coords[axis_index].inner;
        };
        return self.format1.filter_range_min <= coord and
            coord <= self.format1.filter_range_max;
    }
};

const FeatureVariationRecord = struct {
    conditions: parser.Offset32,
    substitutions: parser.Offset32,

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
