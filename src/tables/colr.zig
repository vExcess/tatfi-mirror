//! A [Color Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/colr) implementation.

// NOTE: Parts of the implementation have been inspired by
// [skrifa](https://github.com/googlefonts/fontations/tree/main/skrifa).

const cfg = @import("config");
const parser = @import("../parser.zig");
const delta_set = @import("../delta_set.zig");
const var_store = @import("../var_store.zig");
const cpal = @import("cpal.zig");

const GlyphId = @import("../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;
const LazyArray32 = parser.LazyArray32;
const Offset32 = parser.Offset32;
const NonZeroOffset32 = parser.NonZeroOffset32;
const Offset24 = parser.Offset24;

/// A [Color Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/colr).
pub const Table = struct {
    palettes: cpal.Table,
    data: []const u8,
    version: u8,

    // v0
    base_glyphs: LazyArray16(BaseGlyphRecord),
    layers: LazyArray16(LayerRecord),

    // v1
    base_glyph_paints_offset: Offset32,
    base_glyph_paints: LazyArray32(BaseGlyphPaintRecord),
    layer_paint_offsets_offset: Offset32,
    layer_paint_offsets: LazyArray32(Offset32),
    clip_list_offsets_offset: Offset32,
    clip_list: ClipList,
    variable_fonts: if (cfg.variable_fonts) struct {
        var_index_map: ?delta_set.DeltaSetIndexMap = null,
        item_variation_store: ?var_store.ItemVariationStore = null,
    } else void,

    /// Parses a table from raw data.
    pub fn parse(
        palettes: cpal.Table,
        data: []const u8,
    ) ?Table {
        var s = parser.Stream.new(data);

        const version = s.read(u16) orelse return null;
        if (version > 1) return null;

        const num_base_glyphs = s.read(u16) orelse return null;
        const base_glyphs_offset = s.read(Offset32) orelse return null;
        const layers_offset = s.read(Offset32) orelse return null;
        const num_layers = s.read(u16) orelse return null;

        const base_glyphs = bg: {
            var sbg = parser.Stream.new_at(data, base_glyphs_offset[0]) orelse
                return null;
            break :bg sbg.read_array(BaseGlyphRecord, num_base_glyphs) orelse
                return null;
        };

        const layers = l: {
            var sl = parser.Stream.new_at(data, layers_offset[0]) orelse
                return null;
            break :l sl.read_array(LayerRecord, num_layers) orelse return null;
        };

        var table: Table = .{
            .version = @truncate(version),
            .data = data,
            .palettes = palettes,
            .base_glyphs = base_glyphs,
            .layers = layers,

            .base_glyph_paints_offset = .{0}, // the actual value doesn't matter
            .base_glyph_paints = .{},
            .layer_paint_offsets_offset = .{0},
            .layer_paint_offsets = .{},
            .clip_list_offsets_offset = .{0},
            .clip_list = .{},
            .variable_fonts = if (cfg.variable_fonts) .{},
        };

        if (version == 0) return table;

        table.base_glyph_paints_offset = s.read(Offset32) orelse return null;
        const layer_list_offset = s.read(NonZeroOffset32) orelse return null;
        const clip_list_offset = s.read(NonZeroOffset32) orelse return null;

        const var_index_map_offset = if (cfg.variable_fonts)
            s.read(NonZeroOffset32) orelse return null
        else {};

        const item_variation_offset = if (cfg.variable_fonts)
            s.read(NonZeroOffset32) orelse return null
        else {};

        table.base_glyph_paints = bgp: {
            var sbg = parser.Stream.new_at(data, table.base_glyph_paints_offset[0]) orelse return null;
            const count = sbg.read(u32) orelse return null;
            break :bgp sbg.read_array(BaseGlyphPaintRecord, count) orelse return null;
        };

        if (layer_list_offset[0] != 0) {
            const offset = layer_list_offset[0];
            table.layer_paint_offsets_offset = .{offset};

            var sll = parser.Stream.new_at(data, offset) orelse return null;
            const count = sll.read(u32) orelse return null;

            table.layer_paint_offsets = sll.read_array(Offset32, count) orelse
                return null;
        }

        if (clip_list_offset[0] != 0) {
            const offset = clip_list_offset[0];
            table.clip_list_offsets_offset = .{offset};

            if (offset > data.len) return null;
            const clip_data = data[offset..];

            var scl = parser.Stream.new(clip_data);
            scl.skip(u8); // Format
            const count = scl.read(u32) orelse return null;
            table.clip_list = .{
                .data = clip_data,
                .records = scl.read_array(ClipRecord, count) orelse return null,
            };
        }

        if (cfg.variable_fonts) {
            if (item_variation_offset[0] != 0) {
                const offset = item_variation_offset[0];

                if (offset > data.len) return null;
                const item_var_data = data[offset..];

                var siv = parser.Stream.new(item_var_data);
                table.variable_fonts.item_variation_store = var_store.ItemVariationStore.parse(&siv) orelse
                    return null;
            }

            if (var_index_map_offset[0] != 0) {
                const offset = var_index_map_offset[0];

                if (offset > data.len) return null;
                const var_index_map_data = data[offset..];

                table.variable_fonts.var_index_map = .{
                    .data = var_index_map_data,
                };
            }
        }

        return table;
    }
};

/// A [base glyph](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyph-and-layer-records).
const BaseGlyphRecord = struct {
    glyph_id: GlyphId,
    first_layer_index: u16,
    num_layers: u16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 6;

        pub fn parse(data: *const [SIZE]u8) ?Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = s.read(GlyphId) orelse return null,
                .first_layer_index = s.read(u16) orelse return null,
                .num_layers = s.read(u16) orelse return null,
            };
        }
    };
};

/// A [layer](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyph-and-layer-records).
const LayerRecord = struct {
    glyph_id: GlyphId,
    palette_index: u16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(data: *const [SIZE]u8) ?Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = s.read(GlyphId) orelse return null,
                .palette_index = s.read(u16) orelse return null,
            };
        }
    };
};

/// A [BaseGlyphPaintRecord](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyphlist-layerlist-and-cliplist).
const BaseGlyphPaintRecord = struct {
    glyph_id: GlyphId,
    paint_table_offset: Offset32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 6;

        pub fn parse(data: *const [SIZE]u8) ?Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = s.read(GlyphId) orelse return null,
                .paint_table_offset = s.read(Offset32) orelse return null,
            };
        }
    };
};

/// A [clip list](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyphlist-layerlist-and-cliplist).
const ClipList = struct {
    data: []const u8 = &.{},
    records: LazyArray32(ClipRecord) = .{},
};

/// A [clip record](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyphlist-layerlist-and-cliplist).
const ClipRecord = struct {
    /// The first glyph ID for the range covered by this record.
    start_glyph_id: GlyphId,
    /// The last glyph ID, *inclusive*, for the range covered by this record.
    end_glyph_id: GlyphId,
    /// The offset to the clip box.
    clip_box_offset: Offset24,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 7;

        pub fn parse(data: *const [SIZE]u8) ?Self {
            var s = parser.Stream.new(data);
            return .{
                .start_glyph_id = s.read(GlyphId) orelse return null,
                .end_glyph_id = s.read(GlyphId) orelse return null,
                .clip_box_offset = s.read(Offset24) orelse return null,
            };
        }
    };
};
