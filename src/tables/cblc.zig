//! A [Color Bitmap Location Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cblc) implementation.

const _ = @import("std");

/// A [Color Bitmap Location Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cblc).
///
/// EBLC and bloc also share the same structure, so this is re-used for them.
pub const Table = struct {
    data: []const u8,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) Table {
        return .{
            .data = data,
        };
    }
};
