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
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u16);
        if (version > 1) return error.ParseFail;

        const num_base_glyphs = try s.read(u16);
        const base_glyphs_offset = try s.read(Offset32);
        const layers_offset = try s.read(Offset32);
        const num_layers = try s.read(u16);

        const base_glyphs = bg: {
            var sbg = try parser.Stream.new_at(data, base_glyphs_offset[0]);
            break :bg try sbg.read_array(BaseGlyphRecord, num_base_glyphs);
        };

        const layers = l: {
            var sl = try parser.Stream.new_at(data, layers_offset[0]);
            break :l try sl.read_array(LayerRecord, num_layers);
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

        table.base_glyph_paints_offset = try s.read(Offset32);
        const layer_list_offset = try s.read(NonZeroOffset32);
        const clip_list_offset = try s.read(NonZeroOffset32);

        const var_index_map_offset = if (cfg.variable_fonts)
            try s.read(NonZeroOffset32)
        else {};

        const item_variation_offset = if (cfg.variable_fonts)
            try s.read(NonZeroOffset32)
        else {};

        table.base_glyph_paints = bgp: {
            var sbg = try parser.Stream.new_at(data, table.base_glyph_paints_offset[0]);
            const count = try sbg.read(u32);
            break :bgp try sbg.read_array(BaseGlyphPaintRecord, count);
        };

        if (layer_list_offset[0] != 0) {
            const offset = layer_list_offset[0];
            table.layer_paint_offsets_offset = .{offset};

            var sll = try parser.Stream.new_at(data, offset);
            const count = try sll.read(u32);

            table.layer_paint_offsets = try sll.read_array(Offset32, count);
        }

        if (clip_list_offset[0] != 0) {
            const offset = clip_list_offset[0];
            table.clip_list_offsets_offset = .{offset};

            if (offset > data.len) return error.ParseFail;
            const clip_data = data[offset..];

            var scl = parser.Stream.new(clip_data);
            scl.skip(u8); // Format
            const count = try scl.read(u32);
            table.clip_list = .{
                .data = clip_data,
                .records = try scl.read_array(ClipRecord, count),
            };
        }

        if (cfg.variable_fonts) {
            if (item_variation_offset[0] != 0) {
                const offset = item_variation_offset[0];

                if (offset > data.len) return error.ParseFail;
                const item_var_data = data[offset..];

                var siv = parser.Stream.new(item_var_data);
                table.variable_fonts.item_variation_store =
                    try var_store.ItemVariationStore.parse(&siv);
            }

            if (var_index_map_offset[0] != 0) {
                const offset = var_index_map_offset[0];

                if (offset > data.len) return error.ParseFail;
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

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = try s.read(GlyphId),
                .first_layer_index = try s.read(u16),
                .num_layers = try s.read(u16),
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

        pub fn parse(data: *const [SIZE]u8) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = try s.read(GlyphId),
                .palette_index = try s.read(u16),
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

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = try s.read(GlyphId) ,
                .paint_table_offset = try s.read(Offset32) ,
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

        pub fn parse(data: *const [SIZE]u8) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .start_glyph_id = try s.read(GlyphId) ,
                .end_glyph_id = try s.read(GlyphId) ,
                .clip_box_offset = try s.read(Offset24) ,
            };
        }
    };
};
