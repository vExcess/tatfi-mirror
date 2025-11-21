//! A [PostScript Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/post) implementation.

const parser = @import("../parser.zig");

const LineMetrics = @import("../lib.zig").LineMetrics;

const Fixed = parser.Fixed;
const LazyArray16 = parser.LazyArray16;

const ITALIC_ANGLE_OFFSET: usize = 4;
const UNDERLINE_POSITION_OFFSET: usize = 8;
const UNDERLINE_THICKNESS_OFFSET: usize = 10;
const IS_FIXED_PITCH_OFFSET: usize = 12;

/// A [PostScript Table](https://docs.microsoft.com/en-us/typography/opentype/spec/post).
pub const Table = struct {
    /// Italic angle in counter-clockwise degrees from the vertical.
    italic_angle: f32,
    /// Underline metrics.
    underline_metrics: LineMetrics,
    /// Flag that indicates that the font is monospaced.
    is_monospaced: bool,
    glyph_indices: LazyArray16(u16),
    names_data: []const u8,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        // Do not check the exact length, because some fonts include
        // padding in table's length in table records, which is incorrect.
        if (data.len < 32) return error.ParseFail;

        var s = parser.Stream.new(data);
        const version = try s.read(u32);

        if (version != 0x00010000 and
            version != 0x00020000 and
            version != 0x00025000 and
            version != 0x00030000 and
            version != 0x00040000)
        {
            return error.ParseFail;
        }

        const italic_angle = try s.read_at(Fixed, ITALIC_ANGLE_OFFSET);

        const underline_metrics: LineMetrics = .{
            .position = try s.read_at(i16, UNDERLINE_POSITION_OFFSET),
            .thickness = try s.read_at(i16, UNDERLINE_THICKNESS_OFFSET),
        };

        const is_monospaced = (try s.read_at(u32, IS_FIXED_PITCH_OFFSET)) != 0;

        // Only version 2.0 of the table has data at the end.
        const names_data, const glyph_indices = if (version == 0x00020000) v: {
            const indices_count = try s.read_at(u16, 32);
            const glyph_indices = try s.read_array(u16, indices_count);
            const names_data = try s.tail();
            break :v .{ names_data, glyph_indices };
        } else .{ &.{}, LazyArray16(u16){} };

        return .{
            .italic_angle = italic_angle.value,
            .underline_metrics = underline_metrics,
            .is_monospaced = is_monospaced,
            .names_data = names_data,
            .glyph_indices = glyph_indices,
        };
    }
};
