//! A [Vertical Metrics Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/hvar) implementation.

const parser = @import("../parser.zig");
const var_store = @import("../var_store.zig");

const Offset32 = parser.Offset32;

/// A [Vertical Metrics Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/hvar).
pub const Table = struct {
    data: []const u8,
    variation_store: var_store.ItemVariationStore,
    advance_height_mapping_offset: ?Offset32,
    tsb_mapping_offset: ?Offset32,
    bsb_mapping_offset: ?Offset32,
    vorg_mapping_offset: ?Offset32,
};
