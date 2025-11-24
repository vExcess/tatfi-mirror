const std = @import("std");
const parser = @import("../../parser.zig");

const GlyphId = @import("../../lib.zig").GlyphId;

/// A [format 10](https://docs.microsoft.com/en-us/typography/opentype/spec/cmap#format-10-trimmed-array)
/// subtable.
pub const Subtable10 = struct {
    /// First character code covered.
    first_code_point: u32,
    /// Array of glyph indices for the character codes covered.
    glyphs: parser.LazyArray32(GlyphId),

    /// Parses a subtable from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Subtable10 {
        var s = parser.Stream.new(data);
        s.skip(u16); // format
        s.skip(u16); // length
        s.skip(u16); // language
        const first_code_point = try s.read(u16);
        const count = try s.read(u32);
        const glyphs = try s.read_array(GlyphId, count);
        return .{
            .first_code_point = first_code_point,
            .glyphs = glyphs,
        };
    }

    /// Returns a glyph index for a code point.
    ///
    /// Returns `null` when `code_point` is larger than `u16`.
    pub fn glyph_index(
        self: Subtable10,
        code_point: u21,
    ) ?GlyphId {
        const idx = std.math.sub(u32, code_point, self.first_code_point) catch return null;
        return self.glyphs.get(idx);
    }

    /// Calls `f` for each codepoint defined in this table.
    pub fn codepoints(
        self: Subtable10,
        ctx: anytype,
        F: fn (u32, @TypeOf(ctx)) void,
    ) void {
        for (0..self.glyphs.len()) |i| {
            const code_point = std.math.add(u32, self.first_code_point, @truncate(i)) catch continue;
            F(code_point, ctx);
        }
    }
};
