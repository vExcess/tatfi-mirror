const std = @import("std");
const parser = @import("../../parser.zig");

const StringId = @import("../cff.zig").StringId;
const GlyphId = @import("../../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;

pub const Charset = union(enum) {
    iso_adobe,
    expert,
    expert_subset,
    format0: LazyArray16(StringId),
    format1: LazyArray16(Format1Range),
    format2: LazyArray16(Format2Range),

    pub fn parse_charset(
        number_of_glyphs: u16,
        s: *parser.Stream,
    ) parser.Error!Charset {
        // -1 everywhere, since `.notdef` is omitted.
        const format = try s.read(u8);
        switch (format) {
            0 => return .{ .format0 = try s.read_array(StringId, number_of_glyphs - 1) },
            1 => {
                // The number of ranges is not defined, so we have to
                // read until no glyphs are left.
                var count: u16 = 0;
                {
                    var s_cloned: parser.Stream = .{
                        .data = s.data,
                        .offset = s.offset,
                    };
                    var total_left = number_of_glyphs - 1;
                    while (total_left > 0) {
                        s_cloned.skip(StringId);
                        const left = try s_cloned.read(u8);
                        total_left = try std.math.sub(u16, total_left, left + 1);
                        count += 1;
                    }
                }

                return .{ .format1 = try s.read_array(Format1Range, count) };
            },
            2 => {
                // The same as format 1, but Range::left is u16.
                var count: u16 = 0;
                {
                    var s_cloned: parser.Stream = .{
                        .data = s.data,
                        .offset = s.offset,
                    };
                    var total_left = number_of_glyphs - 1;
                    while (total_left > 0) {
                        s_cloned.skip(StringId);
                        const left = try s_cloned.read(u16);
                        total_left = try std.math.sub(u16, total_left, left + 1);
                        count += 1;
                    }
                }
                return .{ .format2 = try s.read_array(Format2Range, count) };
            },
            else => return error.ParseFail,
        }
    }

    pub fn sid_to_gid(
        self: Charset,
        sid: StringId,
    ) ?GlyphId {
        if (sid[0] == 0) return .{0};

        switch (self) {
            .iso_adobe,
            .expert,
            .expert_subset,
            => return null,
            .format0 => |array| {
                // First glyph is omitted, so we have to add 1.
                var iter = array.iterator();
                var pos: usize = 0;
                while (iter.next()) |n| : (pos += 1) {
                    if (n[0] == sid[0]) return .{@truncate(pos + 1)};
                } else return null;
            },
            .format1 => |array| {
                var id: u16 = 1;
                var iter = array.iterator();
                while (iter.next()) |range| {
                    const last = @as(u32, range.first[0]) + range.left;
                    if (range.first[0] <= sid[0] and sid[0] <= last) {
                        id += sid[0] - range.first[0];
                        return .{id};
                    }

                    id += range.left + 1;
                } else return null;
            },
            .format2 => |array| {
                // The same as format 1, but Range::left is u16.
                var id: u16 = 1;
                var iter = array.iterator();
                while (iter.next()) |range| {
                    const last = @as(u32, range.first[0]) + range.left;
                    if (range.first[0] <= sid[0] and sid[0] <= last) {
                        id += sid[0] - range.first[0];
                        return .{id};
                    }

                    id += range.left + 1;
                } else return null;
            },
        }
    }
};

pub const Format1Range = struct {
    first: StringId,
    left: u8,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 3;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .first = try s.read(StringId),
                .left = try s.read(u8),
            };
        }
    };
};

pub const Format2Range = struct {
    first: StringId,
    left: u16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .first = try s.read(StringId),
                .left = try s.read(u16),
            };
        }
    };
};
