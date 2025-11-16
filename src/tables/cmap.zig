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
};
