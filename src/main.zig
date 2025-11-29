const std = @import("std");
const tetfy = @import("tetfy");

pub fn main() !void {
    defer std.debug.print(
        \\compiled successfully
        \\
    , .{});

    // [ARS] Original intent of this file was to make sure all functions compile, due to Zig's
    // lazy compilation model. Meanwhile, it has turned into a record of the library's public
    // interface.

    // Face methods
    var face = tetfy.Face.parse("true", 0) catch return;
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
    const weight = face.weight();
    _ = weight.to_number();
    const width = face.width();
    _ = width.to_number();
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
    // use a real implementation of the OutlineBuilder interface
    _ = face.outline_glyph(failing_allocator, .{6}, tetfy.OutlineBuilder.dummy_builder);
    _ = face.glyph_bounding_box(failing_allocator, .{53});
    const r = face.global_bounding_box();
    _ = r.width();
    _ = r.height();

    _ = face.glyph_raster_image(.{63}, 54);
    _ = face.glyph_svg_image(.{64});
    _ = face.is_color_glyph(.{54});
    _ = face.color_palettes();
    _ = face.paint_color_glyph(.{64}, 16, white, unsafe_painter) catch {};

    _ = face.variation_axes();
    _ = face.set_variation(tetfy.Tag{ .inner = 4 }, 300.0); // mutable method
    _ = face.variation_coordinates();
    _ = face.has_non_default_variation_coordinates();

    _ = face.glyph_phantom_points(failing_allocator, .{55});

    const raw_tables: tetfy.RawFaceTables = .{};
    _ = tetfy.Face.from_raw_tables(raw_tables) catch {};

    // RawFace methods
    const raw_face = face.raw_face;
    _ = raw_face.table(tetfy.Tag{ .inner = 43 });

    // FaceTables methods
    const tables = face.tables;
    _ = tables.head;
    _ = tables.hhea;
    _ = tables.maxp;
    _ = tables.bdat;
    const cbdt = tables.cbdt;
    if (cbdt) |table| _ = table.get(.{64}, 0);
    const cff = tables.cff;
    if (cff) |table| {
        _ = table.outline(.{64}, tetfy.OutlineBuilder.dummy_builder) catch {};
        _ = table.glyph_index(64);
        _ = table.glyph_width(.{64});
        _ = table.glyph_index_by_name("name");
        _ = table.glyph_name(.{64});
        _ = table.glyph_cid(.{65});
    }
    // TODO: Fill out the rest
    _ = tables.cmap; // Subtables
    _ = tables.colr;
    _ = tables.ebdt;
    _ = tables.glyf;
    _ = tables.hmtx;
    _ = tables.kern;
    _ = tables.name;
    _ = tables.os2;
    _ = tables.post;
    _ = tables.sbix;
    _ = tables.stat;
    _ = tables.svg;
    _ = tables.vhea;
    _ = tables.vmtx;
    _ = tables.vorg;
    _ = tables.opentype_layout.gdef;
    _ = tables.opentype_layout.gpos;
    _ = tables.opentype_layout.gsub;
    _ = tables.opentype_layout.math;
    _ = tables.apple_layout.ankr;
    _ = tables.apple_layout.feat;
    _ = tables.apple_layout.kerx;
    _ = tables.apple_layout.morx;
    _ = tables.apple_layout.trak;
    _ = tables.variable_fonts.avar;
    _ = tables.variable_fonts.cff2;
    _ = tables.variable_fonts.fvar;
    _ = tables.variable_fonts.gvar;
    _ = tables.variable_fonts.hvar;
    _ = tables.variable_fonts.mvar;
    _ = tables.variable_fonts.vvar;
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

const unsafe_painter = tetfy.tables.colr.Painter{
    .ptr = undefined,
    .vtable = undefined,
};

const white: tetfy.RgbaColor = .{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };
