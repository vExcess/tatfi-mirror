//! A [Vertical Origin Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/vorg) implementation.

const parser = @import("../parser.zig");

const GlyphId = @import("../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;

/// A [Vertical Origin Table](https://docs.microsoft.com/en-us/typography/opentype/spec/vorg).
pub const Table = struct {
    /// Default origin.
    default_y: i16,
    /// A list of metrics for each glyph.
    ///
    /// Ordered by `glyph_id`.
    metrics: LazyArray16(VerticalOriginMetrics),

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        const default_y = try s.read(i16);
        const count = try s.read(u16);
        const metrics = try s.read_array(VerticalOriginMetrics, count);

        return .{
            .default_y = default_y,
            .metrics = metrics,
        };
    }
};

/// Vertical origin metrics for the
/// [Vertical Origin Table](https://docs.microsoft.com/en-us/typography/opentype/spec/vorg).
pub const VerticalOriginMetrics = struct {
    /// Glyph ID.
    glyph_id: GlyphId,
    /// Y coordinate, in the font's design coordinate system, of the vertical origin.
    y: i16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .glyph_id = try s.read(GlyphId),
                .y = try s.read(i16),
            };
        }
    };
};
