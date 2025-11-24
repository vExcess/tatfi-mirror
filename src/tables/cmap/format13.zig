const std = @import("std");
const parser = @import("../../parser.zig");

const GlyphId = @import("../../lib.zig").GlyphId;
pub const SequentialMapGroup = @import("format12.zig").SequentialMapGroup;

/// A [format 13](https://docs.microsoft.com/en-us/typography/opentype/spec/cmap#format-13-segmented-coverage)
/// subtable.
pub const Subtable13 = struct {
    groups: parser.LazyArray32(SequentialMapGroup),

    /// Parses a subtable from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Subtable13 {
        var s = parser.Stream.new(data);
        s.skip(u16); // format
        s.skip(u16); // reserved
        s.skip(u32); // length
        s.skip(u32); // language
        const count = try s.read(u32);
        const groups = try s.read_array(SequentialMapGroup, count);
        return .{ .groups = groups };
    }

    /// Returns a glyph index for a code point.
    ///
    /// Returns `null` when `code_point` is larger than `u16`.
    pub fn glyph_index(
        self: Subtable13,
        code_point: u21,
    ) ?GlyphId {
        var iter = self.groups.iterator();
        while (iter.next()) |group| {
            const start_char_code = group.start_char_code;
            if (code_point >= start_char_code and
                code_point <= group.end_char_code)
            {
                const id = std.math.cast(u16, group.start_glyph_id) orelse return null;
                return .{id};
            }
        } else return null;
    }

    /// Calls `f` for each codepoint defined in this table.
    pub fn codepoints(
        self: Subtable13,
        ctx: anytype,
        F: fn (u32, @TypeOf(ctx)) void,
    ) void {
        var iter = self.groups.iterator();
        while (iter.next()) |group| {
            var code_point = group.start_char_code;
            while (code_point <= group.end_char_code) : (code_point += 1)
                F(code_point, ctx);
        }
    }
};
