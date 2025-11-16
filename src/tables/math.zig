//! A [Math Table](https://docs.microsoft.com/en-us/typography/opentype/spec/math) implementation.

const parser = @import("../parser.zig");

const GlyphId = @import("../lib.zig").GlyphId;
const Coverage = @import("../ggg.zig").Coverage;
const Device = @import("gpos.zig").Device;

const LazyArray16 = parser.LazyArray16;
const LazyOffsetArray16 = parser.LazyOffsetArray16;
const Offset16 = parser.Offset16;

/// A [Math Table](https://docs.microsoft.com/en-us/typography/opentype/spec/math).
pub const Table = struct {
    /// Math positioning constants.
    constants: ?Constants,
    /// Per-glyph positioning information.
    glyph_info: ?GlyphInfo,
    /// Variants and assembly recipes for growable glyphs.
    variants: ?Variants,
};

/// A [Math Constants Table](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathconstants-table).
pub const Constants = struct {
    data: []const u8,
};

/// A [Math Glyph Info Table](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathglyphinfo-table).
pub const GlyphInfo = struct {
    /// Per-glyph italics correction values.
    italic_corrections: ?MathValues,
    /// Per-glyph horizontal positions for attaching mathematical accents.
    top_accent_attachments: ?MathValues,
    /// Glyphs which are _extended shapes_.
    extended_shapes: ?Coverage,
    /// Per-glyph information for mathematical kerning.
    kern_infos: ?KernInfos,
};

/// A [Math Variants Table](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathvariants-table).
pub const Variants = struct {
    /// Minimum overlap of connecting glyphs during glyph construction, in design units.
    min_connector_overlap: u16,
    /// Constructions for shapes growing in the vertical direction.
    vertical_constructions: GlyphConstructions,
    /// Constructions for shapes growing in the horizontal direction.
    horizontal_constructions: GlyphConstructions,
};

/// A mapping from glyphs to
/// [Math Values](https://docs.microsoft.com/en-us/typography/opentype/spec/math#mathvaluerecord).
pub const MathValues = struct {
    data: []const u8,
    coverage: Coverage,
    records: LazyArray16(MathValueRecord),
};

/// A math value record with unresolved offset.
const MathValueRecord = struct {
    value: i16,
    device_offset: ?Offset16,
};

/// A [Math Kern Info Table](https://docs.microsoft.com/en-us/typography/opentype/spec/math#mathkerninfo-table).
pub const KernInfos = struct {
    data: []const u8,
    coverage: Coverage,
    records: LazyArray16(KernInfoRecord),
};

const KernInfoRecord = struct {
    top_right: ?Offset16,
    top_left: ?Offset16,
    bottom_right: ?Offset16,
    bottom_left: ?Offset16,
};

/// A mapping from glyphs to
/// [Math Glyph Construction Tables](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathglyphconstruction-table).
pub const GlyphConstructions = struct {
    coverage: Coverage,
    constructions: LazyOffsetArray16(GlyphConstruction),
};

/// A [Math Glyph Construction Table](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathglyphconstruction-table).
pub const GlyphConstruction = struct {
    /// A general recipe on how to construct a variant with large advance width/height.
    assembly: ?GlyphAssembly,
    /// Prepared variants of the glyph with varying advances.
    variants: LazyArray16(GlyphVariant),
};

/// A [Glyph Assembly Table](https://learn.microsoft.com/en-us/typography/opentype/spec/math#glyphassembly-table).
pub const GlyphAssembly = struct {
    /// The italics correction of the assembled glyph.
    italics_correction: MathValue,
    /// Parts the assembly is composed of.
    parts: LazyArray16(GlyphPart),
};

/// A [Math Value](https://docs.microsoft.com/en-us/typography/opentype/spec/math#mathvaluerecord)
/// with optional device corrections.
pub const MathValue = struct {
    /// The X or Y value in font design units.
    value: i16,
    /// Device corrections for this value.
    device: ?Device,
};

/// Description of math glyph variants.
pub const GlyphVariant = struct {
    /// The ID of the variant glyph.
    variant_glyph: GlyphId,
    /// Advance width/height, in design units, of the variant glyph.
    advance_measurement: u16,
};

/// Details for a glyph part in an assembly.
pub const GlyphPart = struct {
    /// Glyph ID for the part.
    glyph_id: GlyphId,
    /// Lengths of the connectors on the start of the glyph, in font design units.
    start_connector_length: u16,
    /// Lengths of the connectors on the end of the glyph, in font design units.
    end_connector_length: u16,
    /// The full advance of the part, in font design units.
    full_advance: u16,
    /// Part flags.
    part_flags: PartFlags,
};

/// Glyph part flags.
pub const PartFlags = struct { u16 };
