//! A [Color Palette Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cpal) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

/// A [Color Palette Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cpal).
pub const Table = struct {
    color_indices: LazyArray16(u16),
    colors: LazyArray16(BgraColor),

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) ?Table {
        var s = parser.Stream.new(data);

        const version = s.read(u16) orelse return null;
        if (version > 1) return null;

        s.skip(u16); // number of palette entries

        const num_palettes = s.read(u16) orelse return null;
        if (num_palettes == 0) return null; // zero palettes is an error

        const num_colors = s.read(u16) orelse return null;
        const color_records_offset = s.read(Offset32) orelse return null;
        const color_indices = s.read_array(u16, num_palettes) orelse return null;

        var colors_stream = parser.Stream.new_at(data, color_records_offset[0]) orelse
            return null;
        const colors = colors_stream.read_array(BgraColor, num_colors) orelse return null;

        return .{
            .color_indices = color_indices,
            .colors = colors,
        };
    }
};

const BgraColor = struct {
    blue: u8,
    green: u8,
    red: u8,
    alpha: u8,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(data: *const [SIZE]u8) ?Self {
            var s = parser.Stream.new(data);
            return .{
                .blue = s.read(u8) orelse return null,
                .green = s.read(u8) orelse return null,
                .red = s.read(u8) orelse return null,
                .alpha = s.read(u8) orelse return null,
            };
        }
    };
};
