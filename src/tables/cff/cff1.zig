//! A [Compact Font Format Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cff) implementation.

// Useful links:
// http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/font/pdfs/5176.CFF.pdf
// http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/font/pdfs/5177.Type2.pdf
// https://github.com/opentypejs/opentype.js/blob/master/src/tables/cff.js

const parser = @import("../../parser.zig");

const Index = @import("index.zig").Index;
const Charset = @import("charset.zig").Charset;
const Encoding = @import("encoding.zig").Encoding;
const StringId = @import("../cff.zig").StringId;

const LazyArray16 = parser.LazyArray16;

/// A [Compact Font Format Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cff).
pub const Table = struct {
    // The whole CFF table.
    // Used to resolve a local subroutine in a CID font.
    table_data: []const u8,

    strings: Index,
    global_subrs: Index,
    charset: Charset,
    number_of_glyphs: u16, // nonzero
    matrix: Matrix,
    char_strings: Index,
    kind: FontKind,

    // Copy of Face::units_per_em().
    // Required to do glyph outlining, since coordinates must be scaled up by this before applying the `matrix`.
    units_per_em: ?u16,
};

/// An affine transformation matrix.
//[ARS] I dont know what affine means here
pub const Matrix = struct {
    sx: f32 = 0,
    ky: f32 = 0,
    kx: f32 = 0,
    sy: f32 = 0.001,
    tx: f32 = 0,
    ty: f32 = 0,
};

pub const FontKind = union(enum) {
    sid: SIDMetadata,
    cid: CIDMetadata,
};

pub const SIDMetadata = struct {
    local_subrs: Index,
    /// Can be zero.
    default_width: f32,
    /// Can be zero.
    nominal_width: f32,
    encoding: Encoding,
};

pub const CIDMetadata = struct {
    fd_array: Index,
    fd_select: FDSelect,
};

pub const FDSelect = union(enum) {
    format0: LazyArray16(u8),
    format3: []const u8, // It's easier to parse it in-place.
};
