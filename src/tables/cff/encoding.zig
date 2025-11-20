const parser = @import("../../parser.zig");

const StringId = @import("../cff.zig").StringId;

const LazyArray16 = parser.LazyArray16;

pub const Encoding = struct {
    kind: EncodingKind,
    supplemental: LazyArray16(Supplement),

    pub const new_standard: Encoding = .{
        .kind = .standard,
        .supplemental = .{},
    };

    pub const new_expert: Encoding = .{
        .kind = .expert,
        .supplemental = .{},
    };

    pub fn parse(
        s: *parser.Stream,
    ) parser.Error!Encoding {
        const has_supplemental, const format = f: {
            const format = try s.read(u8);
            // The first high-bit in format indicates that a Supplemental encoding is present.
            // Check it and clear.
            break :f .{ format & 0x80 != 0, format & 0x7f };
        };

        const count: u16 = try s.read(u8);
        const kind: EncodingKind = switch (format) {
            0 => .{ .format0 = try s.read_array(u8, count) },
            1 => .{ .format1 = try s.read_array(Format1Range, count) },
            else => return error.ParseFail,
        };

        const supplemental: LazyArray16(Supplement) = if (has_supplemental) s: {
            const suppl_count: u16 = try s.read(u8);
            break :s try s.read_array(Supplement, suppl_count);
        } else .{};

        return .{ .kind = kind, .supplemental = supplemental };
    }
};

pub const EncodingKind = union(enum) {
    standard,
    expert,
    format0: LazyArray16(u8),
    format1: LazyArray16(Format1Range),
};

pub const Supplement = struct {
    code: u8,
    name: StringId,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 3;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .code = try s.read(u8),
                .name = try s.read(StringId),
            };
        }
    };
};

pub const Format1Range = struct {
    first: u8,
    left: u8,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 2;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .first = try s.read(u8),
                .left = try s.read(u8),
            };
        }
    };
};
