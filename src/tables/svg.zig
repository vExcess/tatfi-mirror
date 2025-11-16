//! An [SVG Table](https://docs.microsoft.com/en-us/typography/opentype/spec/svg) implementation.

const parser = @import("../parser.zig");

const GlyphId = @import("../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

/// An [SVG Table](https://docs.microsoft.com/en-us/typography/opentype/spec/svg).
pub const Table = struct {
    /// A list of SVG documents.
    documents: SvgDocumentsList,
};

/// A list of [SVG documents](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/svg#svg-document-list).
pub const SvgDocumentsList = struct {
    data: []const u8,
    records: LazyArray16(SvgDocumentRecord),
};

const SvgDocumentRecord = struct {
    start_glyph_id: GlyphId,
    end_glyph_id: GlyphId,
    svg_doc_offset: ?Offset32,
    svg_doc_length: u32,
};
