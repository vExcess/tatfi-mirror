//! A [Compact Font Format 2 Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cff2) implementation.

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2charstr

const Index = @import("index.zig").Index;
const ItemVariationStore = @import("../../var_store.zig").ItemVariationStore;

/// A [Compact Font Format 2 Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2).
pub const Table = struct {
    global_subrs: Index,
    local_subrs: Index,
    char_strings: Index,
    item_variation_store: ItemVariationStore,
};
