//! Implementation of Item Variation Store
//!
//! <https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#item-variation-store>

const std = @import("std");
const parser = @import("parser.zig");

const LazyArray16 = parser.LazyArray16;

pub const ItemVariationStore = struct {
    data: []const u8 = &.{},
    data_offsets: LazyArray16(u32) = .{},
    regions: VariationRegionList = .{},

    pub fn parse(
        s: *parser.Stream,
    ) parser.Error!ItemVariationStore {
        const data = try s.tail();

        var regions_s: parser.Stream = .{
            .data = s.data,
            .offset = s.offset,
        };
        const format = try s.read(u16);
        if (format != 1) return error.ParseFail;

        const region_list_offset = try s.read(u32);
        const count = try s.read(u16);
        const offsets = try s.read_array(u32, count);

        const regions: VariationRegionList = r: {
            regions_s.advance(region_list_offset);
            // [RazrFalcon] TODO: should be the same as in `fvar`
            const axis_count = try regions_s.read(u16);
            const regions_count = try regions_s.read(u16);
            const total = std.math.mul(u16, regions_count, axis_count) catch
                return error.ParseFail;

            break :r .{
                .axis_count = axis_count,
                .regions = try regions_s.read_array(RegionAxisCoordinatesRecord, total),
            };
        };

        return .{
            .data = data,
            .data_offsets = offsets,
            .regions = regions,
        };
    }
};

pub const VariationRegionList = struct {
    axis_count: u16 = 0,
    regions: LazyArray16(RegionAxisCoordinatesRecord) = .{},
};

const RegionAxisCoordinatesRecord = struct {
    start_coord: i16,
    peak_coord: i16,
    end_coord: i16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 6;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .start_coord = try s.read(i16),
                .peak_coord = try s.read(i16),
                .end_coord = try s.read(i16),
            };
        }
    };
};
