//! A [Horizontal Metrics Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/hvar) implementation.

const parser = @import("../parser.zig");
const ItemVariationStore = @import("../var_store.zig").ItemVariationStore;

const Offset32 = parser.Offset32;

/// A [Horizontal Metrics Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/hvar).
pub const Table = struct {
    data: []const u8,
    variation_store: ItemVariationStore,
    advance_width_mapping_offset: ?Offset32,
    lsb_mapping_offset: ?Offset32,
    rsb_mapping_offset: ?Offset32,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s: parser.Stream = .new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        const variation_store_offset = try s.read(Offset32);
        var var_store_s: parser.Stream = try .new_at(data, variation_store_offset[0]);
        const variation_store: ItemVariationStore = try .parse(&var_store_s);

        return .{
            .data = data,
            .variation_store = variation_store,
            .advance_width_mapping_offset = try s.read_optional(Offset32),
            .lsb_mapping_offset = try s.read_optional(Offset32),
            .rsb_mapping_offset = try s.read_optional(Offset32),
        };
    }
};
