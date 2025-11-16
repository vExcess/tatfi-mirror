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
        var_index_map: ?delta_set.DeltaSetIndexMap,
        item_variation_store: ?var_store.ItemVariationStore,
    } else void,
};

/// A [base glyph](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyph-and-layer-records).
const BaseGlyphRecord = struct {
    glyph_id: GlyphId,
    first_layer_index: u16,
    num_layers: u16,
};

/// A [layer](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyph-and-layer-records).
const LayerRecord = struct {
    glyph_id: GlyphId,
    palette_index: u16,
};

/// A [BaseGlyphPaintRecord](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyphlist-layerlist-and-cliplist).
const BaseGlyphPaintRecord = struct {
    glyph_id: GlyphId,
    paint_table_offset: Offset32,
};

/// A [clip list](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/colr#baseglyphlist-layerlist-and-cliplist).
const ClipList = struct {
    data: []const u8,
    records: LazyArray32(ClipRecord),
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
};
