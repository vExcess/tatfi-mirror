//! Implementation of Item Variation Store
//!
//! <https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#item-variation-store>

const parser = @import("parser.zig");

const LazyArray16 = parser.LazyArray16;

pub const ItemVariationStore = struct {
    data: []const u8,
    data_offsets: LazyArray16(u32),
    regions: VariationRegionList,
};

pub const VariationRegionList = struct {
    axis_count: u16,
    regions: LazyArray16(RegionAxisCoordinatesRecord),
};

const RegionAxisCoordinatesRecord = struct {
    start_coord: i16,
    peak_coord: i16,
    end_coord: i16,
};
