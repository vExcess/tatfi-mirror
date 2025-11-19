//! A [Glyph Data Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/glyf) implementation.

const loca = @import("loca.zig");

/// A [Glyph Data Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/glyf).
pub const Table = struct {
    data: []const u8,
    loca_table: loca.Table,

    /// Parses a table from raw data.
    pub fn parse(
        loca_table: loca.Table,
        data: []const u8,
    ) Table {
        return .{
            .data = data,
            .loca_table = loca_table,
        };
    }
};
