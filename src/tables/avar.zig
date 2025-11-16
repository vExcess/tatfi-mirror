//! An [Axis Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/avar) implementation.

const _ = @import("std");

/// An [Axis Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/avar).
pub const Table = struct {
    /// The segment maps array — one segment map for each axis
    /// in the order of axes specified in the `fvar` table.
    segment_maps: SegmentMaps,
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
