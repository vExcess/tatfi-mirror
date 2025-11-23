//! A [Naming Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/name) implementation.

const std = @import("std");
const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;

/// A [Naming Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/name).
pub const Table = struct {
    /// A list of names.
    names: Names = .{},

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        // https://docs.microsoft.com/en-us/typography/opentype/spec/name#naming-table-format-1
        const LANG_TAG_RECORD_SIZE: u16 = 4;

        var s = parser.Stream.new(data);

        const version = try s.read(u16);
        const count = try s.read(u16);
        const storage_offset: usize = (try s.read(Offset16))[0];

        switch (version) {
            0 => {}, // Do nothing.
            1 => {
                const lang_tag_count = try s.read(u16);
                const lang_tag_len = try std.math.mul(u16, lang_tag_count, LANG_TAG_RECORD_SIZE);

                s.advance(lang_tag_len); // langTagRecords
            },
            else => return error.ParseFail, // Unsupported version.
        }

        const records = try s.read_array(NameRecord, count);

        if (s.offset < storage_offset)
            s.advance(storage_offset - s.offset);

        const storage = try s.tail();

        return .{ .names = .{
            .records = records,
            .storage = storage,
        } };
    }
};

/// A list of face names.
pub const Names = struct {
    records: LazyArray16(NameRecord) = .{} ,
    storage: []const u8 = &.{},
};

const NameRecord = struct {
    platform_id: PlatformId,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    length: u16,
    offset: Offset16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 12;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .platform_id = try s.read(PlatformId),
                .encoding_id = try s.read(u16),
                .language_id = try s.read(u16),
                .name_id = try s.read(u16),
                .length = try s.read(u16),
                .offset = try s.read(Offset16),
            };
        }
    };
};

/// A [platform ID](https://docs.microsoft.com/en-us/typography/opentype/spec/name#platform-ids).
pub const PlatformId = enum {
    unicode,
    macintosh,
    iso,
    windows,
    custom,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 2;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            const u = std.mem.readInt(u16, data, .big);
            return switch (u) {
                0 => .unicode,
                1 => .macintosh,
                2 => .iso,
                3 => .windows,
                4 => .custom,
                else => error.ParseFail,
            };
        }
    };
};
