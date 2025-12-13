//! A [Tracking Table](
//! https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6trak.html) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;
const Fixed = parser.Fixed;

/// A [Tracking Table](
/// https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6trak.html).
pub const Table = struct {
    /// Horizontal track data.
    horizontal: TrackData,
    /// Vertical track data.
    vertical: TrackData,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        if (try s.read(u32) != 0x00010000) return error.ParseFail; // version

        if (try s.read(u16) != 0) return error.ParseFail; // format

        const hor_offset = try s.read_optional(Offset16);
        const ver_offset = try s.read_optional(Offset16);
        s.skip(u16); // reserved

        const horizontal: TrackData = if (hor_offset) |offset|
            try .parse(offset[0], data)
        else
            .{};
        const vertical: TrackData = if (ver_offset) |offset|
            try .parse(offset[0], data)
        else
            .{};

        return .{
            .horizontal = horizontal,
            .vertical = vertical,
        };
    }
};

/// A track data.
pub const TrackData = struct {
    /// A list of tracks.
    tracks: Tracks = .{},
    /// A list of sizes.
    sizes: LazyArray16(Fixed) = .{},

    fn parse(
        offset: usize,
        data: []const u8,
    ) parser.Error!TrackData {
        var s = try parser.Stream.new_at(data, offset);

        const tracks_count = try s.read(u16);
        const sizes_count = try s.read(u16);
        const size_table_offset = try s.read(Offset32); // Offset from start of the table.

        const tracks: Tracks = .{
            .data = data,
            .records = try s.read_array(TrackTableRecord, tracks_count),
            .sizes_count = sizes_count,
        };

        // TODO: Isn't the size table is directly after the tracks table?!
        //       Why we need an offset then?
        const sizes = s: {
            var subs = try parser.Stream.new_at(data, size_table_offset[0]);
            break :s try subs.read_array(Fixed, sizes_count);
        };

        return .{
            .tracks = tracks,
            .sizes = sizes,
        };
    }
};

/// A list of tracks.
pub const Tracks = struct {
    data: []const u8 = &.{}, // the whole table
    records: LazyArray16(TrackTableRecord) = .{},
    sizes_count: u16 = 0,
};

const TrackTableRecord = struct {
    value: Fixed,
    name_id: u16,
    offset: Offset16, // Offset from start of the table.

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 8;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            return try parser.parse_struct_from_data(Self, data);
        }
    };
};
