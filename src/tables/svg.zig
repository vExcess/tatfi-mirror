//! An [SVG Table](https://docs.microsoft.com/en-us/typography/opentype/spec/svg) implementation.

const parser = @import("../parser.zig");

const GlyphId = @import("../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;
const NonZeroOffset32 = parser.NonZeroOffset32;

/// An [SVG Table](https://docs.microsoft.com/en-us/typography/opentype/spec/svg).
pub const Table = struct {
    /// A list of SVG documents.
    documents: SvgDocumentsList,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        s.skip(u16); // version

        const doc_list_offset = try s.read(NonZeroOffset32);
        if (doc_list_offset[0] == 0) return error.ParseFail;

        const count = try s.read_at(u16, doc_list_offset[0]);
        const records = try s.read_array(SvgDocumentRecord, count);

        return .{ .documents = .{
            .data = data[doc_list_offset[0]..],
            .records = records,
        } };
    }
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
    svg_doc_offset: NonZeroOffset32,
    svg_doc_length: u32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 12;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .start_glyph_id = try s.read(GlyphId),
                .end_glyph_id = try s.read(GlyphId),
                .svg_doc_offset = try s.read(NonZeroOffset32),
                .svg_doc_length = try s.read(u32),
            };
        }
    };
};
