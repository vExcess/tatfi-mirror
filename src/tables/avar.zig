//! An [Axis Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/avar) implementation.

const parser = @import("../parser.zig");

/// An [Axis Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/avar).
pub const Table = struct {
    /// The segment maps array — one segment map for each axis
    /// in the order of axes specified in the `fvar` table.
    segment_maps: SegmentMaps,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        s.skip(u16); // reserved

        return .{
            .segment_maps = .{
                // TODO: check that `axisCount` is the same as in `fvar`?
                .count = try s.read(u16),
                .data = try s.tail(),
            },
        };
    }
};

/// A list of segment maps.
///
/// Can be empty.
///
/// The internal data layout is not designed for random access,
/// therefore we're not providing the `get()` method and only an iterator.
pub const SegmentMaps = struct {
    count: u16,
    data: []const u8,
};
