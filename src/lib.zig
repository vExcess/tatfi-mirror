/// A high-level, safe, zero-allocation font parser for:
/// * [TrueType](https://docs.microsoft.com/en-us/typography/truetype/),
/// * [OpenType](https://docs.microsoft.com/en-us/typography/opentype/spec/), and
/// * [AAT](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6AATIntro.html).
///
/// Font parsing starts with a [`Face`].
const cfg = @import("config");
const parser = @import("parser.zig");
const tables = @import("tables.zig");
const opentype_layout = @import("ggg.zig");

const LazyArray16 = parser.LazyArray16;

/// A type-safe wrapper for glyph ID.
pub const GlyphId = struct { u16 };

/// A font face.
///
/// Provides a high-level API for working with TrueType fonts.
/// If you're not familiar with how TrueType works internally, you should use this type.
/// If you do know and want a bit more low-level access - checkout [`FaceTables`].
///
/// Note that `Face` doesn't own the font data and doesn't allocate anything in heap.
/// Therefore you cannot "store" it. The idea is that you should parse the `Face`
/// when needed, get required data and forget about it.
/// That's why the initial parsing is highly optimized and should not become a bottleneck.
///
/// Noe that this struct is almost 2KB big.
pub const Face = struct {
    raw_face: RawFace,
    tables: FaceTables, // Parsed tables.
    coordinates: if (cfg.variable_fonts) VarCoords else void,

    const Self = @This();

    /// Creates a new [`Face`] from a raw data.
    ///
    /// `index` indicates the specific font face in a font collection.
    /// Use [`fonts_in_collection`] to get the total number of font faces.
    /// Set to 0 if unsure.
    ///
    /// This method will do some parsing and sanitization,
    /// but in general can be considered free. No significant performance overhead.
    ///
    /// Required tables: `head`, `hhea` and `maxp`.
    ///
    /// If an optional table has invalid data it will be skipped.
    pub fn parse(
        data: []u8,
        index: u32,
    ) FaceParsingError!Self {
        const raw_face = try RawFace.parse(data, index);
        const raw_tables: RawFaceTables = Self.collect_tables(raw_face);

        var face: Self = .{
            .raw_face = raw_face,
            .tables = try Self.parse_tables(raw_tables),
            .coordinates = if (cfg.variable_fonts) VarCoords{},
        };

        if (cfg.variable_fonts) {
            if (face.tables.variable_fonts.fvar) |fvar| {
                // TODO
                _ = fvar;
                _ = &face;
                // face.coordinates.len = fvar.axes.len().min(MAX_VAR_COORDS as u16) as u8;
            }
        }

        return face;
    }

    fn collect_tables(
        raw_face: RawFace,
    ) RawFaceTables {
        _ = raw_face;
        var ret_tables: RawFaceTables = .{};
        // TODO
        _ = &ret_tables;

        return ret_tables;
    }

    fn parse_tables(
        raw_tables: RawFaceTables,
    ) FaceParsingError!FaceTables {
        _ = raw_tables;
        // TODO
        return error.UnknownMagic;
    }
};

/// A raw font face.
///
/// You are probably looking for [`Face`]. This is a low-level type.
///
/// Unlike [`Face`], [`RawFace`] parses only face table records.
/// Meaning all you can get from this type is a raw (`[]const u8`) data of a requested table.
/// Then you can either parse just a singe table from a font/face or populate [`RawFaceTables`]
/// manually before passing it to [`Face.from_raw_tables`].
pub const RawFace = struct {
    /// The input font file data.
    data: []const u8,
    /// An array of table records.
    table_records: LazyArray16(TableRecord),

    const Self = @This();

    /// Creates a new [`RawFace`] from a raw data.
    ///
    /// `index` indicates the specific font face in a font collection.
    /// Use [`fonts_in_collection`] to get the total number of font faces.
    /// Set to 0 if unsure.
    ///
    /// While we do reuse [`FaceParsingError`], `No*Table` errors will not be throws.
    pub fn parse(
        data: []u8,
        index: u32,
    ) FaceParsingError!Self {
        // TODO
        _ = data;
        _ = index;
        return error.UnknownMagic;
    }
};

/// Parsed face tables.
///
/// Unlike [`Face`], provides a low-level parsing abstraction over TrueType tables.
/// Useful when you need a direct access to tables data.
///
/// Also, used when high-level API is problematic to implement.
/// A good example would be OpenType layout tables (GPOS/GSUB).
pub const FaceTables = struct {
    // Mandatory tables.
    head: tables.head.Table,
    hhea: tables.hhea.Table,
    maxp: tables.maxp.Table,

    bdat: ?tables.cbdt.Table = null,
    cbdt: ?tables.cbdt.Table = null,
    cff: ?tables.cff1.Table = null,
    cmap: ?tables.cmap.Table = null,
    colr: ?tables.colr.Table = null,
    ebdt: ?tables.cbdt.Table = null,
    glyf: ?tables.glyf.Table = null,
    hmtx: ?tables.hmtx.Table = null,
    kern: ?tables.kern.Table = null,
    name: ?tables.name.Table = null,
    os2: ?tables.os2.Table = null,
    post: ?tables.post.Table = null,
    sbix: ?tables.sbix.Table = null,
    stat: ?tables.stat.Table = null,
    svg: ?tables.svg.Table = null,
    vhea: ?tables.vhea.Table = null,
    vmtx: ?tables.hmtx.Table = null,
    vorg: ?tables.vorg.Table = null,

    opentype_layout: if (cfg.opentype_layout) struct {
        gdef: ?tables.gdef.Table = null,
        gpos: ?opentype_layout.LayoutTable = null,
        gsub: ?opentype_layout.LayoutTable = null,
        math: ?tables.math.Table = null,
    } else void,

    apple_layout: if (cfg.apple_layout) struct {
        ankr: ?tables.ankr.Table = null,
        feat: ?tables.feat.Table = null,
        kerx: ?tables.kerx.Table = null,
        morx: ?tables.morx.Table = null,
        trak: ?tables.trak.Table = null,
    } else void,

    variable_fonts: if (cfg.variable_fonts) struct {
        avar: ?tables.avar.Table = null,
        cff2: ?tables.cff2.Table = null,
        fvar: ?tables.fvar.Table = null,
        gvar: ?tables.gvar.Table = null,
        hvar: ?tables.hvar.Table = null,
        mvar: ?tables.mvar.Table = null,
        vvar: ?tables.vvar.Table = null,
    } else void,
};

/// A list of all supported tables as raw data.
///
/// This type should be used in tandem with
/// [`Face.from_raw_tables()`](struct.Face.html#method.from_raw_tables).
///
/// This allows loading font faces not only from TrueType font files,
/// but from any source. Mainly used for parsing WOFF.
pub const RawFaceTables = struct {
    // Mandatory tables.
    /// Font Header, global information about the font, version number, creation and modification dates, revision number, and basic typographic data.
    head: []const u8 = &.{},
    /// Horizontal Header, information needed to layout fonts whose characters are written horizontally.
    hhea: []const u8 = &.{},
    /// Maximum Profile, establishes the memory requirements for a font.
    maxp: []const u8 = &.{},

    /// Bitmap data table
    bdat: ?[]const u8 = null,
    /// Bitmap Location, availability of bitmaps at requested point sizes.
    bloc: ?[]const u8 = null,
    /// Color Bitmap Data, used to embed color bitmap glyph data.
    cbdt: ?[]const u8 = null,
    /// Color Bitmap Location, provides locators for embedded color bitmaps.
    cblc: ?[]const u8 = null,
    /// Compact Font Format 1
    cff: ?[]const u8 = null,
    /// Character to Glyph Mapping, maps character codes to glyph indices.
    cmap: ?[]const u8 = null,
    /// Color, adds support for multi-colored glyphs.
    colr: ?[]const u8 = null,
    /// Color Palette, a set of one or more color palettes.
    cpal: ?[]const u8 = null,
    /// Embedded Bitmap Data, embed monochrome or grayscale bitmap glyph data.
    ebdt: ?[]const u8 = null,
    /// Embedded Bitmap Location, provides embedded bitmap locators.
    eblc: ?[]const u8 = null,
    /// Glyph Outline, data that defines the appearance of the glyphs.
    glyf: ?[]const u8 = null,
    /// Horizontal Metrics, metric information for the horizontal layout each of the glyphs.
    hmtx: ?[]const u8 = null,
    /// Kern, values that adjust the intercharacter spacing for glyphs.
    kern: ?[]const u8 = null,
    /// Glyph Data Location, stores the offsets to the locations of the glyphs.
    loca: ?[]const u8 = null,
    /// Font Names, human-readable names for features and settings, copyright, font names, style names, and other information.
    name: ?[]const u8 = null,
    /// OS/2 Compatibility, a set of metrics that are required by Windows.
    os2: ?[]const u8 = null,
    /// Glyph Name and PostScript Font, information needed to use a TrueType font on a PostScript printer.
    post: ?[]const u8 = null,
    /// Extended Bitmaps, provides access to bitmap data in a standard graphics format (such as PNG, JPEG, TIFF).
    sbix: ?[]const u8 = null,
    /// Style Attributes, describes design attributes that distinguish font-style variants within a font family.
    stat: ?[]const u8 = null,
    /// Scalable Vector Graphics, contains SVG descriptions for some or all of the glyphs in the font.
    svg: ?[]const u8 = null,
    /// Vertical Header, information needed for vertical fonts.
    vhea: ?[]const u8 = null,
    /// Vertical Metrics, specifies the vertical spacing for each glyph in an AAT vertical font.
    vmtx: ?[]const u8 = null,
    /// Vertical Origin, the y coordinate of a glyph’s vertical origin, this can only be used in CFF or CFF2 fonts.
    vorg: ?[]const u8 = null,

    opentype_layout: if (cfg.opentype_layout) struct {
        /// Glyph Definition, provides various glyph properties used in OpenType Layout processing.
        gdef: ?[]const u8 = null,
        /// Glyph Positioning, precise control over glyph placement for sophisticated text layout in each supported script.
        gpos: ?[]const u8 = null,
        /// Glyph Substitution, provides data for substitution of glyphs for appropriate rendering of different scripts.
        gsub: ?[]const u8 = null,
        /// Mathematical Typesetting, font-specific information necessary for math formula layout.
        math: ?[]const u8 = null,
    } else void = if (cfg.opentype_layout) .{},

    apple_layout: if (cfg.apple_layout) struct {
        /// Anchor Point Table, defines anchor points.
        ankr: ?[]const u8 = null,
        /// Feature Name Table, font's text features.
        feat: ?[]const u8 = null,
        /// Kerx, extended kerning table.
        kerx: ?[]const u8 = null,
        /// Extended Glyph Metamorphosis, specifies a set of transformations that can apply to the glyphs of your font.
        morx: ?[]const u8 = null,
        /// Tracking, allows AAT fonts to adjust to normal interglyph spacing.
        trak: ?[]const u8 = null,
    } else void = if (cfg.apple_layout) .{},

    variable_fonts: if (cfg.variable_fonts) struct {
        /// Axis Variation Table, allows the font to modify the mapping between axis values and these normalized values.
        avar: ?[]const u8 = null,
        /// Compact Font Format 2
        cff2: ?[]const u8 = null,
        /// Font Variations Table, global information of which variation axes are included in the font.
        fvar: ?[]const u8 = null,
        /// Glyph Variations Table, includes all of the data required for stylizing the glyphs.
        gvar: ?[]const u8 = null,
        /// Horizontal Metrics Variations Table, used in variable fonts to provide glyph variations for horizontal glyph metrics values.
        hvar: ?[]const u8 = null,
        /// Metrics Variations Table, used in variable fonts to provide glyph variations for font-wide metric values found in other font tables.
        mvar: ?[]const u8 = null,
        /// Vertical Metrics Variations Table, used in variable fonts to provide glyph variations for vertical glyph metric values.
        vvar: ?[]const u8 = null,
    } else void = if (cfg.variable_fonts) .{},
};

/// A raw table record.
pub const TableRecord = struct {
    tag: Tag,
    check_sum: u32,
    offset: u32,
    length: u32,
};

/// A 4-byte tag.
pub const Tag = struct { u32 };

/// A list of font face parsing errors.
pub const FaceParsingError = error{
    /// An attempt to read out of bounds detected.
    ///
    /// Should occur only on malformed fonts.
    MalformedFont,

    /// Face data must start with `0x00010000`, `0x74727565`, `0x4F54544F` or `0x74746366`.
    UnknownMagic,

    /// The face index is larger than the number of faces in the font.
    FaceIndexOutOfBounds,

    /// The `head` table is missing or malformed.
    NoHeadTable,

    /// The `hhea` table is missing or malformed.
    NoHheaTable,

    /// The `maxp` table is missing or malformed.
    NoMaxpTable,
};

/// A rectangle.
///
/// Doesn't guarantee that `x_min` <= `x_max` and/or `y_min` <= `y_max`.
pub const Rect = struct {
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

/// A line metrics.
///
/// Used for underline and strikeout.
pub const LineMetrics = struct {
    /// Line position.
    position: i16,
    /// Line thickness.
    thickness: i16,
};

// VARIABLE FONTS
// [ARS] These should get compiled out if variable_fonts option is false
const MAX_VAR_COORDS: u7 = 64;
const VarCoords = struct {
    data: [MAX_VAR_COORDS]NormalizedCoordinate = @splat(.{ .inner = 0 }),
    len: u8 = 0,
};

/// A variation coordinate in a normalized coordinate system.
///
/// Basically any number in a -1.0..1.0 range.
/// Where 0 is a default value.
///
/// The number is stored as f2.16
pub const NormalizedCoordinate = struct { inner: i16 };
