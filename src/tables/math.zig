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

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        if (try s.read(u16) != 1) return error.ParseFail; // major version
        s.skip(u16); // minor version

        const constants = parse_at_offset(Constants, &s, data) catch null;
        const glyph_info = parse_at_offset(GlyphInfo, &s, data) catch null;
        const variants = parse_at_offset(Variants, &s, data) catch null;

        return .{
            .constants = constants,
            .glyph_info = glyph_info,
            .variants = variants,
        };
    }
};

/// A [Math Constants Table](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathconstants-table).
pub const Constants = struct {
    data: []const u8,

    fn parse(
        data: []const u8,
    ) parser.Error!Constants {
        return .{ .data = data };
    }
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

    fn parse(
        data: []const u8,
    ) parser.Error!GlyphInfo {
        var s = parser.Stream.new(data);

        const italic_corrections = parse_at_offset(MathValues, &s, data) catch null;
        const top_accent_attachments = parse_at_offset(MathValues, &s, data) catch null;
        const extended_shapes = parse_at_offset(Coverage, &s, data) catch null;
        const kern_infos = parse_at_offset(KernInfos, &s, data) catch null;

        return .{
            .italic_corrections = italic_corrections,
            .top_accent_attachments = top_accent_attachments,
            .extended_shapes = extended_shapes,
            .kern_infos = kern_infos,
        };
    }
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

    fn parse(
        data: []const u8,
    ) parser.Error!Variants {
        var s = parser.Stream.new(data);

        const min_connector_overlap = try s.read(u16);
        const vertical_coverage = parse_at_offset(Coverage, &s, data) catch null;
        const horizontal_coverage = parse_at_offset(Coverage, &s, data) catch null;

        const vertical_count = try s.read(u16);
        const horizontal_count = try s.read(u16);
        const vertical_offsets = try s.read_array_optional(Offset16, vertical_count);
        const horizontal_offsets = try s.read_array_optional(Offset16, horizontal_count);

        return .{
            .min_connector_overlap = min_connector_overlap,
            .vertical_constructions = .new(
                data,
                vertical_coverage,
                vertical_offsets,
            ),
            .horizontal_constructions = .new(
                data,
                horizontal_coverage,
                horizontal_offsets,
            ),
        };
    }
};

/// A mapping from glyphs to
/// [Math Values](https://docs.microsoft.com/en-us/typography/opentype/spec/math#mathvaluerecord).
pub const MathValues = struct {
    data: []const u8,
    coverage: Coverage,
    records: LazyArray16(MathValueRecord),

    fn parse(
        data: []const u8,
    ) parser.Error!MathValues {
        var s = parser.Stream.new(data);
        const coverage = try parse_at_offset(Coverage, &s, data);
        const count = try s.read(u16);
        const records = try s.read_array(MathValueRecord, count);
        return .{
            .data = data,
            .coverage = coverage,
            .records = records,
        };
    }
};

/// A math value record with unresolved offset.
const MathValueRecord = struct {
    value: i16,
    device_offset: ?Offset16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .value = try s.read(i16),
                .device_offset = try s.read_optional(Offset16),
            };
        }
    };
};

/// A [Math Kern Info Table](https://docs.microsoft.com/en-us/typography/opentype/spec/math#mathkerninfo-table).
pub const KernInfos = struct {
    data: []const u8,
    coverage: Coverage,
    records: LazyArray16(KernInfoRecord),

    fn parse(data: []const u8) parser.Error!KernInfos {
        var s = parser.Stream.new(data);
        const coverage = try parse_at_offset(Coverage, &s, data);
        const count = try s.read(u16);
        const records = try s.read_array(KernInfoRecord, count);

        return .{
            .data = data,
            .coverage = coverage,
            .records = records,
        };
    }
};

const KernInfoRecord = struct {
    top_right: ?Offset16,
    top_left: ?Offset16,
    bottom_right: ?Offset16,
    bottom_left: ?Offset16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 8;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .top_right = try s.read_optional(Offset16),
                .top_left = try s.read_optional(Offset16),
                .bottom_right = try s.read_optional(Offset16),
                .bottom_left = try s.read_optional(Offset16),
            };
        }
    };
};

/// A mapping from glyphs to
/// [Math Glyph Construction Tables](
/// https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathglyphconstruction-table).
pub const GlyphConstructions = struct {
    coverage: Coverage,
    constructions: LazyOffsetArray16(GlyphConstruction),

    fn new(
        data: []const u8,
        coverage: ?Coverage,
        offsets: LazyArray16(?Offset16),
    ) GlyphConstructions {
        return .{
            .coverage = coverage orelse .{ .format1 = .{ .glyphs = .{} } },
            .constructions = .new(data, offsets),
        };
    }
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

fn parse_at_offset(
    T: type,
    s: *parser.Stream,
    data: []const u8,
) parser.Error!T {
    const offset = try s.read_optional(Offset16) orelse return error.ParseFail;
    if (offset[0] > data.len) return error.ParseFail;

    return try T.parse(data[offset[0]..]);
}
