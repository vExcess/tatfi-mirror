const std = @import("std");
const ttf = @import("tatfi");

pub fn main() !void {
    defer std.debug.print(
        \\compiled successfully
        \\
    , .{});

    // [ARS] Original intent of this file was to make sure all functions compile, due to Zig's
    // lazy compilation model. Meanwhile, it has turned into a record of the library's public
    // interface.

    // Face methods
    var face = ttf.Face.parse("true", 0) catch return;
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
    _ = face.outline_glyph(failing_allocator, .{6}, ttf.OutlineBuilder.dummy_builder);
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
    _ = face.set_variation(ttf.Tag{ .inner = 4 }, 300.0); // mutable method
    _ = face.variation_coordinates();
    _ = face.has_non_default_variation_coordinates();

    _ = face.glyph_phantom_points(failing_allocator, .{55});

    const raw_tables: ttf.RawFaceTables = .{};
    _ = ttf.Face.from_raw_tables(raw_tables) catch {};

    // RawFace methods
    const raw_face = face.raw_face;
    _ = raw_face.table(ttf.Tag{ .inner = 43 });

    // FaceTables methods
    const tables = face.tables;
    _ = tables.head;
    _ = tables.hhea;
    _ = tables.maxp;
    _ = tables.bdat;
    if (tables.cbdt) |cbdt| _ = cbdt.get(.{64}, 0);
    if (tables.cff) |cff| {
        _ = cff.outline(.{64}, ttf.OutlineBuilder.dummy_builder) catch {};
        _ = cff.glyph_index(64);
        _ = cff.glyph_width(.{64});
        _ = cff.glyph_index_by_name("name");
        _ = cff.glyph_name(.{64});
        _ = cff.glyph_cid(.{65});
    }
    if (tables.cmap) |cmap| {
        const sts = cmap.subtables;
        const st = sts.get(0).?;
        _ = st.is_unicode();
        _ = st.glyph_index(54);
        _ = st.glyph_variation_index(4, 4);
        _ = st.codepoints(@as(u32, 1), func);
    }
    if (tables.colr) |colr| {
        _ = colr.is_simple();
        _ = colr.contains(.{4});
        // the following two methods are called through `face.paint_color_glyph`
        _ = colr.clip_box(.{5}, &.{});
        _ = colr.paint(.{4}, 0, unsafe_painter, &.{}, white) catch {};
    }
    _ = tables.ebdt;
    if (tables.glyf) |glyf| {
        _ = glyf.outline(.{5}, ttf.OutlineBuilder.dummy_builder);
        _ = glyf.bbox(.{4});
    }
    _ = tables.hmtx;
    if (tables.kern) |kern| {
        const subtables = kern.subtables;
        var iter = subtables.iterator();
        while (iter.next()) |subtable|
            _ = subtable.glyphs_kerning(.{5}, .{4});
    }
    if (tables.name) |name| {
        const names = name.names;
        _ = names.get(4);
        var iter = names.iterator();
        while (iter.next()) |n| {
            _ = n.to_string(failing_allocator);
            _ = n.language();
        }
    }
    if (tables.os2) |os2| {
        // direcly called by methods on Face
        _ = os2.weight();
        _ = os2.width();
        _ = os2.permissions();
        _ = os2.is_subsetting_allowed();
        _ = os2.is_outline_embedding_allowed();
        _ = os2.subscript_metrics();
        _ = os2.superscript_metrics();
        _ = os2.strikeout_metrics();
        _ = os2.unicode_ranges();
        _ = os2.style();
        _ = os2.is_bold();
        _ = os2.use_typographic_metrics();
        _ = os2.typographic_ascender();
        _ = os2.typographic_descender();
        _ = os2.typographic_line_gap();
        _ = os2.windows_ascender();
        _ = os2.windows_descender();
        _ = os2.x_height();
        _ = os2.capital_height();
    }
    if (tables.post) |post| {
        _ = post.glyph_name(.{5});
        _ = post.glyph_index_by_name("name");
        var iter = post.names();
        while (iter.next()) |_| {}
    }
    if (tables.sbix) |sbix| {
        _ = sbix.best_strike(5);
        const strikes = sbix.strikes;
        _ = strikes.get(4);
        _ = strikes.len();
        var iter = strikes.iterator();
        while (iter.next()) |strike| {
            _ = strike.get(.{4});
            _ = strike.len();
        }
    }
    if (tables.stat) |stat| {
        var iter = stat.subtables();
        while (iter.next()) |subtable| {
            _ = subtable.value();
            _ = subtable.contains(.{ .value = 0 });
            _ = subtable.name_id();
            _ = subtable.is_elidable();
            _ = subtable.is_older_sibling();
        }
        _ = stat.subtable_for_axis(.{ .inner = 3 }, null);
    }
    // TODO: Fill out the rest
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

const unsafe_painter = ttf.tables.colr.Painter{
    .ptr = undefined,
    .vtable = undefined,
};

const white: ttf.RgbaColor = .{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };

fn func(_: u32, _: u32) void {}
