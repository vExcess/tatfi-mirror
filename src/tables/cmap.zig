//!
//! A [Character to Glyph Index Mapping Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cmap) implementation.
//!
//! This module provides a low-level alternative to
//! [`Face::glyph_index`](../struct.Face.html#method.glyph_index) and
//! [`Face::glyph_variation_index`](../struct.Face.html#method.glyph_variation_index)
//! methods.

const parser = @import("../parser.zig");

const PlatformId = @import("name.zig").PlatformId;

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

/// A [Character to Glyph Index Mapping Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cmap).
pub const Table = struct {
    /// A list of subtables.
    subtables: Subtables,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        s.skip(u16); // version

        const count = try s.read(u16);
        const records = try s.read_array(EncodingRecord, count);

        return .{
            .subtables = .{
                .data = data,
                .records = records,
            },
        };
    }
};

/// A list of subtables.
pub const Subtables = struct {
    data: []const u8,
    records: LazyArray16(EncodingRecord),
};

const EncodingRecord = struct {
    platform_id: PlatformId,
    encoding_id: u16,
    offset: Offset32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 8;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .platform_id = try s.read(PlatformId),
                .encoding_id = try s.read(u16),
                .offset = try s.read(Offset32),
            };
        }
    };
};
