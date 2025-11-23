//! A [Metrics Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/mvar) implementation.

const parser = @import("../parser.zig");
const ItemVariationStore = @import("../var_store.zig").ItemVariationStore;

const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;

/// A [Metrics Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/mvar).
pub const Table = struct {
    variation_store: ItemVariationStore,
    records: LazyArray16(ValueRecord),

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s: parser.Stream = .new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        s.skip(u16);
        const value_record_size = try s.read(u16);

        if (value_record_size != ValueRecord.FromData.SIZE) return error.ParseFail;

        const count = try s.read(u16);
        if (count == 0) return error.ParseFail;

        const var_store_offset = try s.read_optional(Offset16) orelse return error.ParseFail;
        const records = try s.read_array(ValueRecord, count);

        var var_s: parser.Stream = try .new_at(data, var_store_offset[0]);
        const variation_store: ItemVariationStore = try .parse(&var_s);

        return .{
            .records = records,
            .variation_store = variation_store,
        };
    }
};

const ValueRecord = struct {
    value_tag: Tag,
    delta_set_outer_index: u16,
    delta_set_inner_index: u16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 8;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .value_tag = try s.read(Tag),
                .delta_set_outer_index = try s.read(u16),
                .delta_set_inner_index = try s.read(u16),
            };
        }
    };
};
