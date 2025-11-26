const std = @import("std");
const tetfy = @import("tetfy");

pub fn main() !void {
    defer std.debug.print(
        \\compiled successfully
        \\
    , .{});

    const face = tetfy.Face.parse("true", 0) catch return;
    _ = face.raw_face.table(.{ .inner = 53 }) orelse {};
    _ = face.names();
    _ = face.style();
    _ = face.is_bold();
    _ = face.is_italic();
    _ = face.is_monospaced();
    _ = face.is_oblique();
    _ = face.is_variable();
    _ = face.italic_angle();
    _ = face.is_regular();
    _ = face.weight();
    _ = face.width();
    _ = face.ascender();
    _ = face.descender();
    _ = face.line_gap();
    _ = face.vertical_height();
    _ = face.vertical_line_gap();
    _ = face.typographic_ascender();
    _ = face.typographic_descender();
    _ = face.typographic_line_gap();
    _ = face.units_per_em();
    _ = face.x_height();
    _ = face.capital_height();
    _ = face.underline_metrics();
    _ = face.strikeout_metrics();
    _ = face.subscript_metrics();
    _ = face.superscript_metrics();
    _ = face.permissions();
    _ = face.is_subsetting_allowed();
    _ = face.is_outline_embedding_allowed();
    const ur = face.unicode_ranges();
    _ = ur.contains_char('a');
    _ = face.number_of_glyphs();
    _ = face.glyph_index(4);

    _ = face.glyph_index_by_name("boo");
    _ = face.glyph_variation_index(5, 0);

    _ = face.glyph_hor_advance(failing_allocator, .{9});
    _ = face.glyph_ver_advance(failing_allocator, .{9});

    _ = face.glyph_hor_side_bearing(.{3});
    _ = face.glyph_ver_side_bearing(.{3});
    _ = face.glyph_y_origin(.{9});

    _ = face.glyph_name(.{6});

    const raw_tables: tetfy.RawFaceTables = .{};
    _ = tetfy.Face.from_raw_tables(raw_tables) catch {};
}

// [ARS] To be replaced by std.mem.Allocator.failing should zig upgrade to 0.16.*
pub const failing_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};
const vtable: std.mem.Allocator.VTable = .{
    .alloc = noAlloc,
    .resize = std.mem.Allocator.noResize,
    .remap = std.mem.Allocator.noRemap,
    .free = std.mem.Allocator.noFree,
};
fn noAlloc(_: *anyopaque, _: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    return null;
}
