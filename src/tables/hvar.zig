//! A [Horizontal Metrics Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/hvar) implementation.

const parser = @import("../parser.zig");
const var_store = @import("../var_store.zig");

const Offset32 = parser.Offset32;

/// A [Horizontal Metrics Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/hvar).
pub const Table = struct {
    data: []const u8,
    variation_store: var_store.ItemVariationStore,
    advance_width_mapping_offset: ?Offset32,
    lsb_mapping_offset: ?Offset32,
    rsb_mapping_offset: ?Offset32,
};
