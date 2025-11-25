//! A [Glyph Data Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/glyf) implementation.

const std = @import("std");
const parser = @import("../parser.zig");
const loca = @import("loca.zig");

const GlyphId = @import("../lib.zig").GlyphId;
const Transform = @import("../lib.zig").Transform;

const F2DOT14 = parser.F2DOT14;

/// A [Glyph Data Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/glyf).
pub const Table = struct {
    data: []const u8,
    loca_table: loca.Table,

    /// Parses a table from raw data.
    pub fn parse(
        loca_table: loca.Table,
        data: []const u8,
    ) Table {
        return .{
            .data = data,
            .loca_table = loca_table,
        };
    }

    pub fn get(
        self: Table,
        glyph_id: GlyphId,
    ) ?[]const u8 {
        const start, const end = self.loca_table.glyph_range(glyph_id) orelse return null;
        if (start > self.data.len or end > self.data.len) return null;
        return self.data[start..end];
    }

    /// Returns the number of points in this outline.
    pub fn outline_points(
        self: Table,
        glyph_id: GlyphId,
    ) u16 {
        return self.outline_points_impl(glyph_id) catch 0;
    }

    fn outline_points_impl(
        self: Table,
        glyph_id: GlyphId,
    ) parser.Error!u16 {
        const data = self.get(glyph_id) orelse return error.ParseFail;
        var s = parser.Stream.new(data);
        const number_of_contours = try s.read(i16);

        s.advance(8); //  bbox.

        if (number_of_contours > 0) {
            // Simple glyph.
            const glyph_points = try parse_simple_outline(
                try s.tail(),
                @bitCast(number_of_contours),
            );
            return glyph_points.points_left;
        } else if (number_of_contours < 0) {
            // Composite glyph.
            var components = CompositeGlyphIter.new(try s.tail());
            var count: u16 = 0;
            while (components.next()) |_| count += 1;

            return count;
        } else {
            // An empty glyph.
            return error.ParseFail;
        }
    }
};

pub fn parse_simple_outline(
    glyph_data: []const u8,
    number_of_contours: u16, // nonzero,
) parser.Error!GlyphPointsIter {
    var s = parser.Stream.new(glyph_data);
    const endpoints = try s.read_array(u16, number_of_contours);

    const points_total = pt: {
        const last = endpoints.last() orelse return error.ParseFail;
        break :pt try std.math.add(u16, last, 1);
    };

    // Contours with a single point should be ignored.
    // But this is not an error, so we should return an "empty" iterator.
    if (points_total == 1) return .empty;

    // Skip instructions byte code.
    const instructions_len = try s.read(u16);
    s.advance(instructions_len);

    const flags_offset = s.offset;
    if (flags_offset > glyph_data.len) return error.ParseFail;

    const x_coords_len, const y_coords_len = try resolve_coords_len(&s, points_total);

    const x_coords_offset = s.offset;
    if (x_coords_offset > glyph_data.len) return error.ParseFail;

    const y_coords_offset = x_coords_offset + x_coords_len;
    if (y_coords_offset > glyph_data.len) return error.ParseFail;

    const y_coords_end = y_coords_offset + y_coords_len;
    if (y_coords_end > glyph_data.len) return error.ParseFail;

    return .{
        .endpoints = EndpointsIter.new(endpoints) orelse return error.ParseFail,
        .flags = .new(glyph_data[flags_offset..x_coords_offset]),
        .x_coords = .new(glyph_data[x_coords_offset..y_coords_offset]),
        .y_coords = .new(glyph_data[y_coords_offset..y_coords_end]),
        .points_left = points_total,
    };
}

pub const GlyphPointsIter = struct {
    endpoints: EndpointsIter,
    flags: FlagsIter,
    x_coords: CoordsIter,
    y_coords: CoordsIter,
    points_left: u16, // Number of points left in the glyph.

    const empty: GlyphPointsIter = .{
        .endpoints = .{},
        .flags = .{},
        .x_coords = .{},
        .y_coords = .{},
        .points_left = 0,
    };
};

/// A simple flattening iterator for glyph's endpoints.
///
/// Translates endpoints like: 2 4 7
/// into flags: 0 0 1 0 1 0 0 1
const EndpointsIter = struct {
    endpoints: parser.LazyArray16(u16) = .{}, // Each endpoint indicates a contour end.
    index: u16 = 0,
    left: u16 = 0,

    fn new(
        endpoints: parser.LazyArray16(u16),
    ) ?EndpointsIter {
        return .{
            .endpoints = endpoints,
            .index = 1,
            .left = endpoints.get(0) orelse return null,
        };
    }
};

const FlagsIter = struct {
    stream: parser.Stream = .empty,
    // Number of times the `flags` should be used
    // before reading the next one from `stream`.
    repeats: u8 = 0,
    flags: SimpleGlyphFlags = .{},

    fn new(
        data: []const u8,
    ) FlagsIter {
        return .{
            .stream = .new(data),
            .repeats = 0,
            .flags = .{},
        };
    }
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#simple-glyph-description
const SimpleGlyphFlags = packed struct(u8) {
    on_curve_point: bool = false,
    x_short: bool = false,
    y_short: bool = false,
    repeat_flag: bool = false,
    x_is_same_or_positive_short: bool = false,
    y_is_same_or_positive_short: bool = false,
    _0: u2 = 0,
};

const CoordsIter = struct {
    stream: parser.Stream = .empty,
    prev: i16 = 0, // Points are stored as deltas, so we have to keep the previous one.

    fn new(
        data: []const u8,
    ) CoordsIter {
        return .{
            .stream = .new(data),
            .prev = 0,
        };
    }
};

pub const CompositeGlyphIter = struct {
    stream: parser.Stream = .empty,

    pub fn new(
        data: []const u8,
    ) CompositeGlyphIter {
        return .{
            .stream = .new(data),
        };
    }

    pub fn next(
        self: *CompositeGlyphIter,
    ) ?CompositeGlyphInfo {
        const flags = self.stream.read(CompositeGlyphFlags) catch return null;
        const glyph_id = self.stream.read(GlyphId) catch return null;

        var ts: Transform = .{};

        if (flags.args_are_xy_values) {
            if (flags.arg_1_and_2_are_words) {
                ts.e = @floatFromInt(self.stream.read(i16) catch return null);
                ts.f = @floatFromInt(self.stream.read(i16) catch return null);
            } else {
                ts.e = @floatFromInt(self.stream.read(i8) catch return null);
                ts.f = @floatFromInt(self.stream.read(i8) catch return null);
            }
        }

        if (flags.we_have_a_two_by_two) {
            ts.a = (self.stream.read(F2DOT14) catch return null).to_f32();
            ts.b = (self.stream.read(F2DOT14) catch return null).to_f32();
            ts.c = (self.stream.read(F2DOT14) catch return null).to_f32();
            ts.d = (self.stream.read(F2DOT14) catch return null).to_f32();
        } else if (flags.we_have_an_x_and_y_scale) {
            ts.a = (self.stream.read(F2DOT14) catch return null).to_f32();
            ts.d = (self.stream.read(F2DOT14) catch return null).to_f32();
        } else if (flags.we_have_a_scale) {
            ts.a = (self.stream.read(F2DOT14) catch return null).to_f32();
            ts.d = ts.a;
        }

        if (!flags.more_components)
            // Finish the iterator even if stream still has some data.
            self.stream.jump_to_end();

        return .{
            .glyph_id = glyph_id,
            .transform = ts,
            .flags = flags,
        };
    }
};

pub const CompositeGlyphInfo = struct {
    glyph_id: GlyphId,
    transform: Transform,
    flags: CompositeGlyphFlags,
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/glyf#composite-glyph-description
const CompositeGlyphFlags = packed struct(u16) {
    arg_1_and_2_are_words: bool = false,
    args_are_xy_values: bool = false,
    _0: u1 = 0,
    we_have_a_scale: bool = false,
    _1: u1 = 0,
    more_components: bool = false,
    we_have_an_x_and_y_scale: bool = false,
    we_have_a_two_by_two: bool = false,
    _2: u8 = 0,
};

/// Resolves coordinate arrays length.
///
/// The length depends on *Simple Glyph Flags*, so we have to process them all to find it.
fn resolve_coords_len(
    s: *parser.Stream,
    points_total: u16,
) parser.Error!struct { u32, u32 } {
    var flags_left: u32 = points_total;
    var repeats: u32 = undefined;
    var x_coords_len: u32 = 0;
    var y_coords_len: u32 = 0;

    while (flags_left > 0) {
        const flags = try s.read(SimpleGlyphFlags);
        repeats = if (flags.repeat_flag)
            (try s.read(u8)) + 1
        else
            1;

        if (repeats > flags_left) return error.ParseFail;

        // No need to check for `*_coords_len` overflow since u32 is more than enough.

        if (flags.x_short) {
            // Coordinate is 1 byte long.
            x_coords_len += repeats;
        } else if (!flags.x_is_same_or_positive_short) {
            // Coordinate is 2 bytes long.
            x_coords_len += repeats * 2;
        }

        if (flags.y_short) {
            // Coordinate is 1 byte long.
            y_coords_len += repeats;
        } else if (!flags.y_is_same_or_positive_short) {
            // Coordinate is 2 bytes long.
            y_coords_len += repeats * 2;
        }

        // [ARS] Branchless version in Rust OG. Might be faster
        // x_coords_len += (flags.0 & 0x02 != 0) as u32 * repeats;
        // x_coords_len += (flags.0 & (0x02 | 0x10) == 0) as u32 * (repeats * 2);
        //
        // y_coords_len += (flags.0 & 0x04 != 0) as u32 * repeats;
        // y_coords_len += (flags.0 & (0x04 | 0x20) == 0) as u32 * (repeats * 2);

        flags_left -= repeats;
    }

    return .{ x_coords_len, y_coords_len };
}
