//! A [Metrics Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/mvar) implementation.

const parser = @import("../parser.zig");
const var_store = @import("../var_store.zig");

const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;

/// A [Metrics Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/mvar).
pub const Table = struct {
    variation_store: var_store.ItemVariationStore,
    records: LazyArray16(ValueRecord),
};

const ValueRecord = struct {
    value_tag: Tag,
    delta_set_outer_index: u16,
    delta_set_inner_index: u16,
};
