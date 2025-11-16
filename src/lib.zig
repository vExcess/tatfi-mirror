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

/// A raw table record.
pub const TableRecord = struct {
    tag: Tag,
    check_sum: u32,
    offset: u32,
    length: u32,
};

/// A 4-byte tag.
pub const Tag = struct { u32 };

// VARIABLE FONTS
// [ARS] These should get compiled out if variable_fonts option is false
const MAX_VAR_COORDS: usize = 64;
const VarCoords = struct {
    data: [MAX_VAR_COORDS]NormalizedCoordinate,
    len: u8,
};

/// A variation coordinate in a normalized coordinate system.
///
/// Basically any number in a -1.0..1.0 range.
/// Where 0 is a default value.
///
/// The number is stored as f2.16
pub const NormalizedCoordinate = struct { i16 };

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
