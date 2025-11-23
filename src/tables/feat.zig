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

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        if (try s.read(u32) != 0x00010000) return error.ParseFail; // version

        const count = try s.read(u16);
        try s.advance_checked(6); // reserved
        const records = try s.read_array(FeatureNameRecord, count);

        return .{ .names = .{
            .data = data,
            .records = records,
        } };
    }
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

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 12;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .feature = try s.read(u16),
                .setting_table_records_count = try s.read(u16),
                .setting_table_offset = try s.read(Offset32),
                .flags = try s.read(u8),
                .default_setting_index = try s.read(u8),
                .name_index = try s.read(u16),
            };
        }
    };
};
