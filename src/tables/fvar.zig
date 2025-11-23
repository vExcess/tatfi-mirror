//! A [Font Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/fvar) implementation.

const std = @import("std");
const parser = @import("../parser.zig");

const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;
const Fixed = parser.Fixed;

/// A [Font Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/fvar).
pub const Table = struct {
    /// A list of variation axes.
    axes: LazyArray16(VariationAxis),

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        const axes_array_offset = try s.read(Offset16);
        s.skip(u16); // reserved
        const axis_count = try s.read(u16);

        // 'If axisCount is zero, then the font is not functional as a variable font,
        // and must be treated as a non-variable font;
        // any variation-specific tables or data is ignored.'
        if (axis_count == 0) return error.ParseFail;

        s.offset = axes_array_offset[0];
        const axes = try s.read_array(VariationAxis, axis_count);

        return .{ .axes = axes };
    }
};

/// A [variation axis](https://docs.microsoft.com/en-us/typography/opentype/spec/fvar#variationaxisrecord).
pub const VariationAxis = struct {
    tag: Tag,
    min_value: f32,
    def_value: f32,
    max_value: f32,
    /// An axis name in the `name` table.
    name_id: u16,
    hidden: bool,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);

            const tag = try s.read(Tag);
            const min_value = try s.read(Fixed);
            const def_value = try s.read(Fixed);
            const max_value = try s.read(Fixed);
            const flags = try s.read(u16);
            const name_id = try s.read(u16);

            return .{
                .tag = tag,
                .min_value = @min(def_value.value, min_value.value),
                .def_value = def_value.value,
                .max_value = @max(def_value.value, max_value.value),
                .name_id = name_id,
                .hidden = (flags >> 3) & 1 == 1,
            };
        }
    };
};
