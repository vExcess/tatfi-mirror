//! A [Tracking Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6trak.html) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Fixed = parser.Fixed;

/// A [Tracking Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6trak.html).
pub const Table = struct {
    /// Horizontal track data.
    horizontal: TrackData,
    /// Vertical track data.
    vertical: TrackData,
};

/// A track data.
pub const TrackData = struct {
    /// A list of tracks.
    tracks: Tracks,
    /// A list of sizes.
    sizes: LazyArray16(Fixed),
};

/// A list of tracks.
pub const Tracks = struct {
    data: []const u8, // the whole table
    records: LazyArray16(TrackTableRecord),
    sizes_count: u16,
};

const TrackTableRecord = struct {
    value: Fixed,
    name_id: u16,
    offset: Offset16, // Offset from start of the table.
};
