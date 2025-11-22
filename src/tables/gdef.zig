//! A [Glyph Definition Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/gdef) implementation.

const cfg = @import("config");
const parser = @import("../parser.zig");
const var_store = @import("../var_store.zig");

const GlyphId = @import("../lib.zig").GlyphId;
const ClassDefinition = @import("../ggg.zig").ClassDefinition;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;

/// A [Glyph Definition Table](https://docs.microsoft.com/en-us/typography/opentype/spec/gdef).
pub const Table = struct {
    glyph_classes: ?ClassDefinition,
    mark_attach_classes: ?ClassDefinition,
    mark_glyph_coverage_offsets: ?struct { []const u8, LazyArray16(Offset32) },
    variation_store: if (cfg.variable_fonts) ?var_store.ItemVariationStore else void,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        const version = try s.read(u32);

        if (version != 0x00010000 and
            version != 0x00010002 and
            version != 0x00010003) return error.ParseFail;

        const glyph_class_def_offset = try s.read_optional(Offset16);
        s.skip(Offset16); // attachListOffset
        s.skip(Offset16); // ligCaretListOffset
        const mark_attach_class_def_offset = try s.read_optional(Offset16);

        const mark_glyph_sets_def_offset =
            if (version > 0x00010000) try s.read_optional(Offset16) else null;

        const var_store_offset = if (cfg.variable_fonts and version > 0x00010002)
            try s.read_optional(Offset32)
        else
            null;

        return .{
            .glyph_classes = o: {
                const offset = glyph_class_def_offset orelse break :o null;
                if (offset[0] > data.len) break :o null;
                break :o ClassDefinition.parse(data[offset[0]..]) catch null;
            },
            .mark_attach_classes = o: {
                const offset = mark_attach_class_def_offset orelse break :o null;
                if (offset[0] > data.len) break :o null;
                break :o ClassDefinition.parse(data[offset[0]..]) catch null;
            },
            .mark_glyph_coverage_offsets = o: {
                const offset = mark_glyph_sets_def_offset orelse break :o null;
                if (offset[0] > data.len) break :o null;

                const subdata = data[offset[0]..];
                var sub_s = parser.Stream.new(subdata);
                const format = try sub_s.read(u16);

                if (format != 1) break :o null;
                const count = sub_s.read(u16) catch break :o null;
                const array = sub_s.read_array(Offset32, count) catch break :o null;

                break :o .{ subdata, array };
            },
            .variation_store = if (cfg.variable_fonts) o: {
                const offset = var_store_offset orelse break :o null;
                if (offset[0] > data.len) break :o null;

                const subdata = data[offset[0]..];
                var sub_s = parser.Stream.new(subdata);

                break :o var_store.ItemVariationStore.parse(&sub_s) catch null;
            },
        };
    }
};
