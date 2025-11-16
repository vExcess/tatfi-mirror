//! A [Color Bitmap Data Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cbdt) implementation.

const cblc = @import("cblc.zig");

/// A [Color Bitmap Data Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cbdt).
///
/// EBDT and bdat also share the same structure, so this is re-used for them.
pub const Table = struct {
    locations: cblc.Table,
    data: []const u8,
};
