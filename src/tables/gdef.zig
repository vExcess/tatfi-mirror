//! A [Glyph Definition Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/gdef) implementation.

const cfg = @import("config");
const parser = @import("../parser.zig");
const var_store = @import("../var_store.zig");

const GlyphId = @import("../lib.zig").GlyphId;
const ClassDefinition = @import("../ggg.zig").ClassDefinition;

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

/// A [Glyph Definition Table](https://docs.microsoft.com/en-us/typography/opentype/spec/gdef).
pub const Table = struct {
    glyph_classes: ?ClassDefinition,
    mark_attach_classes: ?ClassDefinition,
    mark_glyph_coverage_offsets: ?struct { []const u8, LazyArray16(Offset32) },
    variation_store: if (cfg.variable_fonts) ?var_store.ItemVariationStore else void,
};
