//! A [Style Attributes Table](https://docs.microsoft.com/en-us/typography/opentype/spec/stat) implementation.

const parser = @import("../parser.zig");

const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;

/// A [Style Attributes Table](https://docs.microsoft.com/en-us/typography/opentype/spec/stat).
pub const Table = struct {
    /// List of axes
    axes: LazyArray16(AxisRecord),
    /// Fallback name when everything can be elided.
    fallback_name_id: ?u16,
    version: u32,
    data: []const u8,
    value_lookup_start: Offset32,
    value_offsets: LazyArray16(Offset16),

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        const version = try s.read(u32);

        // Supported versions are:
        // - 1.0
        // - 1.1 adds elidedFallbackNameId
        // - 1.2 adds format 4 axis value table
        if (version != 0x00010000 and
            version != 0x00010001 and
            version != 0x00010002) return error.ParseFail;

        s.skip(u16); // axis_size
        const axis_count = try s.read(u16);
        const axis_offset: usize = (try s.read(Offset32))[0];

        const value_count = try s.read(u16);
        const value_lookup_start = try s.read(Offset32);

        const fallback_name_id = if (version >= 0x00010001)
            // If version >= 1.1 the field is required
            try s.read(u16)
        else
            null;

        const axes = try s.read_array_at(AxisRecord, axis_count, axis_offset);
        const value_offsets = try s.read_array_at(Offset16, value_count, value_lookup_start[0]);

        return .{
            .axes = axes,
            .data = data,
            .value_lookup_start = value_lookup_start,
            .value_offsets = value_offsets,
            .fallback_name_id = fallback_name_id,
            .version = version,
        };
    }
};

/// The [axis record](https://learn.microsoft.com/en-us/typography/opentype/spec/stat#axis-records) struct provides information about a single design axis.
pub const AxisRecord = struct {
    /// Axis tag.
    tag: Tag,
    /// The name ID for entries in the 'name' table that provide a display string for this axis.
    name_id: u16,
    /// Sort order for e.g. composing font family or face names.
    ordering: u16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 8;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .tag = try s.read(Tag),
                .name_id = try s.read(u16),
                .ordering = try s.read(u16),
            };
        }
    };
};
