//! A [Glyph Variations Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/gvar) implementation.

// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#tuple-variation-store

const std = @import("std");
const cfg = @import("config");
const parser = @import("../parser.zig");

const log = std.log.scoped(.gvar);

const GlyphId = @import("../lib.zig").GlyphId;
const NormalizedCoordinate = @import("../lib.zig").NormalizedCoordinate;
const PhantomPoints = @import("../lib.zig").PhantomPoints;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;
const F2DOT14 = parser.F2DOT14;

/// 'The TrueType rasterizer dynamically generates 'phantom' points for each glyph
/// that represent horizontal and vertical advance widths and side bearings,
/// and the variation data within the `gvar` table includes data for these phantom points.'
///
/// We don't actually use them, but they are required during deltas parsing.
const PHANTOM_POINTS_LEN: usize = 4;

/// A [Glyph Variations Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/gvar).
pub const Table = struct {
    axis_count: u16, // nonzero
    shared_tuple_records: LazyArray16(F2DOT14),
    offsets: GlyphVariationDataOffsets,
    glyphs_variation_data: []const u8,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        const version = try s.read(u32);
        if (version != 0x00010000) return error.ParseFail;

        const axis_count = try s.read(u16);

        // The axis count cannot be zero.
        if (axis_count == 0) return error.ParseFail;

        const shared_tuple_count = try s.read(u16);
        const shared_tuples_offset = try s.read(Offset32);
        const glyph_count = try s.read(u16);
        const flags = try s.read(u16);

        const glyph_variation_data_array_offset = try s.read(Offset32);
        if (glyph_variation_data_array_offset[0] > data.len) return error.ParseFail;

        const shared_tuple_records = str: {
            var sub_s = try parser.Stream.new_at(data, shared_tuples_offset[0]);
            const count = try std.math.mul(u16, shared_tuple_count, axis_count);
            break :str try sub_s.read_array(F2DOT14, count);
        };

        const glyphs_variation_data = data[glyph_variation_data_array_offset[0]..];

        const offsets: GlyphVariationDataOffsets = o: {
            const offsets_count = try std.math.add(u16, glyph_count, 1);
            const is_long_format = flags & 1 == 1; // The first bit indicates a long format.
            break :o if (is_long_format)
                .{ .long = try s.read_array(Offset32, offsets_count) }
            else
                .{ .short = try s.read_array(Offset16, offsets_count) };
        };

        return .{
            .axis_count = axis_count,
            .shared_tuple_records = shared_tuple_records,
            .offsets = offsets,
            .glyphs_variation_data = glyphs_variation_data,
        };
    }

    pub fn phantom_points(
        self: Table,
        gpa: std.mem.Allocator,
        glyf_table: @import("glyf.zig").Table,
        coordinates: []const NormalizedCoordinate,
        glyph_id: GlyphId,
    ) ?PhantomPoints {
        const outline_points = glyf_table.outline_points(glyph_id);

        var fba_state = std.heap.stackFallback(VariationTuples.STACK_ALLOCATION_SIZE, gpa);
        const fba = fba_state.get();

        var tuples = VariationTuples.init(fba) catch return null;
        defer tuples.deinit();

        self.parse_variation_data(
            glyph_id,
            coordinates,
            outline_points,
            &tuples,
        ) catch
            return null;

        // Skip all outline deltas.
        for (0..outline_points) |_| _ = tuples.apply_null() orelse return null;

        return .{
            .left = tuples.apply_null() orelse return null,
            .right = tuples.apply_null() orelse return null,
            .top = tuples.apply_null() orelse return null,
            .bottom = tuples.apply_null() orelse return null,
        };
    }

    fn parse_variation_data(
        self: Table,
        glyph_id: GlyphId,
        coordinates: []const NormalizedCoordinate,
        points_len: u16,
        tuples: *VariationTuples,
    ) parser.Error!void {
        tuples.clear();

        if (coordinates.len != self.axis_count) return error.ParseFail;

        const next_glyph_id = try std.math.add(u16, glyph_id[0], 1);

        const start: usize, const end: usize = se: switch (self.offsets) {
            .short => |array| {
                // 'If the short format (Offset16) is used for offsets,
                // the value stored is the offset divided by 2.'
                const start = array.get(glyph_id[0]) orelse return error.ParseFail;
                const end = array.get(next_glyph_id) orelse return error.ParseFail;

                break :se .{ start[0] * 2, end[0] * 2 };
            },
            .long => |array| {
                const start = array.get(glyph_id[0]) orelse return error.ParseFail;
                const end = array.get(next_glyph_id) orelse return error.ParseFail;

                break :se .{ start[0], end[0] };
            },
        };

        if (start == end) return;
        if (start > self.glyphs_variation_data.len or end > self.glyphs_variation_data.len)
            return error.ParseFail;

        const data = self.glyphs_variation_data[start..end];

        return try parse_variation_data_inner(
            coordinates,
            self.shared_tuple_records,
            points_len,
            data,
            tuples,
        );
    }
};

const GlyphVariationDataOffsets = union(enum) {
    short: LazyArray16(Offset16),
    long: LazyArray16(Offset32),
};

/// A list of variation tuples, possibly stored on the heap.
///
/// This is the only part of the `gvar` algorithm that actually allocates a data.
/// This is probably unavoidable due to `gvar` structure,
/// since we have to iterate all tuples in parallel.
const VariationTuples = struct {
    /// this is the allocator used. it must be a stack fallback allocator that
    /// falls back to either an arena or a failing allocator.
    allocator: std.mem.Allocator,
    /// the ArrayList where the items are
    list: std.ArrayList(VariationTuple),

    const STACK_ALLOCATION_SIZE = cfg.gvar_max_stack_tuples_len * @sizeOf(VariationTuple);

    /// input allocator be a stack fallback allocator with size at least
    /// `cfg.gvar_max_stack_tuples_len * @sizeOf(VariationTuple)`
    fn init(
        fba: std.mem.Allocator,
    ) std.mem.Allocator.Error!VariationTuples {
        return .{
            .allocator = fba,
            .list = try .initCapacity(
                fba,
                cfg.gvar_max_stack_tuples_len,
            ),
        };
    }

    fn deinit(
        self: *VariationTuples,
    ) void {
        self.list.deinit(self.allocator);
    }

    /// Remove all tuples from the structure.
    fn clear(
        self: *VariationTuples,
    ) void {
        self.list.clearRetainingCapacity();
    }

    /// Attempt to reserve up to `capacity` total slots for variation tuples.
    fn reserve(
        self: *VariationTuples,
        capacity: u16,
    ) bool {
        self.list.ensureTotalCapacityPrecise(self.allocator, capacity) catch
            return false;
        return true;
    }

    /// Append a new tuple header to the list.
    /// This may panic if the list can't hold a new header.
    // [ARS] maybe better to use `appendBounded`?
    fn push(
        self: *VariationTuples,
        header: VariationTuple,
    ) void {
        self.list.appendAssumeCapacity(header);
    }

    // This is just like `apply()`, but without `infer_deltas`,
    // since we use it only for component points and not a contour.
    // And since there are no contour and no points, `infer_deltas()` will do nothing.
    fn apply_null(
        self: *VariationTuples,
    ) ?PhantomPoints.PointF {
        var x: f32 = 0.0;
        var y: f32 = 0.0;

        for (self.list.items) |*tuple| {
            const x_delta, const y_delta =
                if (tuple.set_points) |*set_points| d: {
                    if (!set_points.next()) continue;
                    break :d tuple.deltas.next() orelse continue;
                } else tuple.deltas.next() orelse continue;

            x += x_delta;
            y += y_delta;
        }

        return .{ .x = x, .y = y };
    }
};

// This structure will be used by the `VariationTuples` stack buffer,
// so it has to be as small as possible.
const VariationTuple = struct {
    set_points: ?PackedPointsIter.SetPointsIter,
    deltas: PackedDeltasIter,
    /// The last parsed point with delta in the contour.
    /// Used during delta resolving.
    prev_point: ?PointAndDelta,
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#tuple-variation-store-header
fn parse_variation_data_inner(
    coordinates: []const NormalizedCoordinate,
    shared_tuple_records: LazyArray16(F2DOT14),
    points_len: u16,
    data: []const u8,
    tuples: *VariationTuples,
) parser.Error!void {
    const SHARED_POINT_NUMBERS_FLAG: u16 = 0x8000;
    const COUNT_MASK: u16 = 0x0FFF;

    var main_stream = parser.Stream.new(data);
    const tuple_variation_count_raw = try main_stream.read(u16);
    const data_offset = try main_stream.read(Offset16);

    // 'The high 4 bits are flags, and the low 12 bits
    // are the number of tuple variation tables for this glyph.'
    const has_shared_point_numbers = tuple_variation_count_raw & SHARED_POINT_NUMBERS_FLAG != 0;
    const tuple_variation_count = tuple_variation_count_raw & COUNT_MASK;

    // 'The number of tuple variation tables can be any number between 1 and 4095.'
    // No need to check for 4095, because this is 0x0FFF that we masked before.
    if (tuple_variation_count == 0) return error.ParseFail;

    // Attempt to reserve space for the tuples we're about to parse.
    // If it fails, bail out.
    if (!tuples.reserve(tuple_variation_count)) {
        // https://github.com/harfbuzz/ttf-parser/issues/194#issuecomment-3073862296
        log.debug(
            \\Given font has {d} vairation tuples. Maximum amount allocatable is {d}.
            \\To get this font's data pass in a working allocator.
        , .{ tuple_variation_count, cfg.gvar_max_stack_tuples_len });

        return error.ParseFail;
    }

    // A glyph variation data consists of three parts: header + variation tuples + serialized data.
    // Each tuple has it's own chunk in the serialized data.
    // Because of that, we are using two parsing streams: one for tuples and one for serialized data.
    // So we can parse them in parallel and avoid needless allocations.
    var serialized_stream = try parser.Stream.new_at(data, data_offset[0]);

    // All tuples in the variation data can reference the same point numbers,
    // which are defined at the start of the serialized data.

    const shared_point_numbers = if (has_shared_point_numbers)
        try PackedPointsIter.new(&serialized_stream)
    else
        null;

    return try parse_variation_tuples(
        tuple_variation_count,
        coordinates,
        shared_tuple_records,
        shared_point_numbers,
        try std.math.add(u16, points_len, PHANTOM_POINTS_LEN),
        &main_stream,
        &serialized_stream,
        tuples,
    );
}

// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#tuplevariationheader
fn parse_variation_tuples(
    count: u16,
    coordinates: []const NormalizedCoordinate,
    shared_tuple_records: LazyArray16(F2DOT14),
    shared_point_numbers: ?PackedPointsIter,
    points_len: u16,
    main_s: *parser.Stream,
    serialized_s: *parser.Stream,
    tuples: *VariationTuples,
) parser.Error!void {
    std.debug.assert(@sizeOf(VariationTuple) <= 80);

    // `TupleVariationHeader` has a variable size, so we cannot use a `LazyArray`.
    for (0..count) |_| {
        const header = try parse_tuple_variation_header(
            coordinates,
            shared_tuple_records,
            main_s,
        );

        if (!(header.scalar > 0.0)) {
            // Serialized data for headers with non-positive scalar should be skipped.
            serialized_s.advance(header.serialized_data_len);
            continue;
        }

        const serialized_data_start = serialized_s.offset;

        // Resolve point numbers source.
        const point_numbers = if (header.has_private_point_numbers)
            try PackedPointsIter.new(serialized_s)
        else
            shared_point_numbers;

        // TODO: this
        // Since the packed representation can include zero values,
        // it is possible for a given point number to be repeated in the derived point number list.
        // In that case, there will be multiple delta values in the deltas data
        // associated with that point number. All of these deltas must be applied
        // cumulatively to the given point.

        const deltas_count = if (point_numbers) |pn| dc: {
            var iter = pn;
            var pn_count: u16 = 0;
            while (iter.next()) |_| pn_count += 1;
            break :dc pn_count;
        } else points_len;

        const deltas = d: {
            // Use `checked_sub` in case we went over the `serialized_data_len`.
            const left = try std.math.sub(
                usize,
                header.serialized_data_len,
                serialized_s.offset - serialized_data_start,
            );

            const deltas_data = try serialized_s.read_bytes(left);
            break :d PackedDeltasIter.new(header.scalar, deltas_count, deltas_data);
        };

        const set_points: ?PackedPointsIter.SetPointsIter =
            if (point_numbers) |pn| .new(pn) else null;

        const tuple = VariationTuple{
            .set_points = set_points,
            .deltas = deltas,
            .prev_point = null,
        };

        tuples.push(tuple);
    }
}

const TupleVariationHeaderData = struct {
    scalar: f32,
    has_private_point_numbers: bool,
    serialized_data_len: u16,
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats#tuplevariationheader
fn parse_tuple_variation_header(
    coordinates: []const NormalizedCoordinate,
    shared_tuple_records: LazyArray16(F2DOT14),
    s: *parser.Stream,
) parser.Error!TupleVariationHeaderData {
    const EMBEDDED_PEAK_TUPLE_FLAG: u16 = 0x8000;
    const INTERMEDIATE_REGION_FLAG: u16 = 0x4000;
    const PRIVATE_POINT_NUMBERS_FLAG: u16 = 0x2000;
    const TUPLE_INDEX_MASK: u16 = 0x0FFF;

    const serialized_data_size = try s.read(u16);
    const tuple_index_raw = try s.read(u16);

    const has_embedded_peak_tuple = tuple_index_raw & EMBEDDED_PEAK_TUPLE_FLAG != 0;
    const has_intermediate_region = tuple_index_raw & INTERMEDIATE_REGION_FLAG != 0;
    const has_private_point_numbers = tuple_index_raw & PRIVATE_POINT_NUMBERS_FLAG != 0;
    const tuple_index = tuple_index_raw & TUPLE_INDEX_MASK;

    const axis_count: u16 = @truncate(coordinates.len);

    const peak_tuple = if (has_embedded_peak_tuple)
        try s.read_array(F2DOT14, axis_count)
    else pt: {
        // Use shared tuples.
        const start = try std.math.mul(u16, tuple_index, axis_count);
        const end = try std.math.add(u16, start, axis_count);

        break :pt shared_tuple_records.slice(start, end) orelse return error.ParseFail;
    };

    const start_tuple: parser.LazyArray16(F2DOT14), const end_tuple: parser.LazyArray16(F2DOT14) =
        if (has_intermediate_region) .{
            try s.read_array(F2DOT14, axis_count),
            try s.read_array(F2DOT14, axis_count),
        } else .{ .{}, .{} };

    var header: TupleVariationHeaderData = .{
        .scalar = 0.0,
        .has_private_point_numbers = has_private_point_numbers,
        .serialized_data_len = serialized_data_size,
    };

    // Calculate the scalar value according to the pseudo-code described at:
    // https://docs.microsoft.com/en-us/typography/opentype/spec/otvaroverview#algorithm-for-interpolation-of-instance-values
    var scalar: f32 = 1.0;
    for (0..axis_count) |i_usize| {
        const i: u16 = @truncate(i_usize);
        const v = coordinates[i].inner;
        const peak = (peak_tuple.get(i) orelse return error.ParseFail).inner;

        if (peak == 0 or v == peak) continue;

        if (has_intermediate_region) {
            const start = (start_tuple.get(i) orelse return error.ParseFail).inner;
            const end = (end_tuple.get(i) orelse return error.ParseFail).inner;

            if (start > peak or
                peak > end or
                (start < 0 and end > 0 and peak != 0)) continue;

            if (v < start or v > end) return header;

            if (v < peak) {
                if (peak != start) {
                    const top: f32 = @floatFromInt(v - start);
                    const bot: f32 = @floatFromInt(peak - start);
                    scalar *= top / bot;
                }
            } else {
                if (peak != end) {
                    const top: f32 = @floatFromInt(end - v);
                    const bot: f32 = @floatFromInt(end - peak);
                    scalar *= top / bot;
                }
            }
        } else if (v == 0 or v < @min(0, peak) or v > @max(0, peak)) {
            // 'If the instance coordinate is out of range for some axis, then the
            // region and its associated deltas are not applicable.'
            return header;
        } else {
            const top: f32 = @floatFromInt(v);
            const bot: f32 = @floatFromInt(peak);
            scalar *= top / bot;
        }
    }

    header.scalar = scalar;
    return header;
}

// This structure will be used by the `VariationTuples` stack buffer,
// so it has to be as small as possible.
// Therefore we cannot use `Stream` and other abstractions.
pub const PackedPointsIter = struct {
    data: []const u8,
    // u16 is enough, since the maximum number of points is 32767.
    offset: u16,
    state: State,
    points_left: u8,

    const State = enum {
        control,
        short_point,
        long_point,
    };

    const Control = packed struct(u8) {
        run_count_mask: u7,
        points_are_words: bool,

        // 'Mask for the low 7 bits to provide the number of point values in the run, minus one.'
        // So we have to add 1.
        // It will never overflow because of a mask.
        fn run_count(
            self: Control,
        ) u8 {
            return self.run_count_mask + 1;
        }
    };

    // The `PackedPointsIter` will return referenced point numbers as deltas.
    // i.e. 1 2 4 is actually 1 3 7
    // But this is not very useful in our current algorithm,
    // so we will convert it once again into:
    // false true false true false false false true
    // This way we can iterate glyph points and point numbers in parallel.
    pub const SetPointsIter = struct {
        iter: PackedPointsIter,
        unref_count: u16,

        pub fn new(iter: PackedPointsIter) SetPointsIter {
            var iterator = iter;
            const unref_count = iterator.next() orelse 0;
            return .{
                .iter = iterator,
                .unref_count = unref_count,
            };
        }

        fn next(
            self: *SetPointsIter,
        ) bool {
            if (self.unref_count != 0) {
                self.unref_count -= 1;
                return false;
            }

            if (self.iter.next()) |unref_count| {
                self.unref_count = unref_count;
                self.unref_count -|= 1;
            }

            // Iterator will be returning `true` after "finished".
            // This is because this iterator will be zipped with the `glyf.GlyphPointsIter`
            // and the number of glyph points can be larger than the amount of set points.
            // Anyway, this is a non-issue in a well-formed font.
            return true;
        }
    };

    pub fn new(
        s: *parser.Stream,
    ) parser.Error!?PackedPointsIter {
        // The total amount of points can be set as one or two bytes
        // depending on the first bit.
        const b1 = try s.read(u8);
        const count: u16 = if (b1 & 0x80 != 0) b: {
            const b2 = try s.read(u8);
            break :b (@as(u16, b1 & 0x7F) << 8) | @as(u16, b2);
        } else b1;

        // No points is not an error.
        if (count == 0) return null;

        const start = s.offset;
        const tail = try s.tail();

        // The actual packed points data size is not stored,
        // so we have to parse the points first to advance the provided stream.
        // Since deltas will be right after points.
        var i: u16 = 0;
        while (i < count) {
            const control = try s.read(Control);
            const run_count: u16 = control.run_count();
            // Do not actually parse the number, simply advance.
            try s.advance_checked(
                if (control.points_are_words) 2 * run_count else run_count,
            );
            i += run_count;
        }

        // No points is not an error.
        if (i == 0) return null;

        // Malformed font.
        if (i > count) return error.ParseFail;

        // Check that points data size is smaller than the storage type
        // used by the iterator.
        const data_len = s.offset - start;
        if (data_len > std.math.maxInt(u16)) return error.ParseFail;

        return .{
            .data = tail[0..data_len],
            .offset = 0,
            .state = .control,
            .points_left = 0,
        };
    }

    fn next(
        self: *PackedPointsIter,
    ) ?u16 {
        if (self.offset >= self.data.len) return null;

        if (self.state == .control) {
            const control: Control = @bitCast(self.data[self.offset]);
            self.offset += 1;

            self.points_left = control.run_count();
            self.state = if (control.points_are_words)
                .long_point
            else
                .short_point;

            return self.next();
        } else {
            var s = parser.Stream.new_at(self.data, self.offset) catch return null;
            const point: u16 = if (self.state == .long_point) l: {
                self.offset += 2;
                break :l s.read(u16) catch return null;
            } else s: {
                self.offset += 1;
                break :s s.read(u8) catch return null;
            };

            self.points_left -= 1;
            if (self.points_left == 0) self.state = .control;

            return point;
        }
    }
};

// This structure will be used by the `VariationTuples` stack buffer,
// so it has to be as small as possible.
// Therefore we cannot use `Stream` and other abstractions.
pub const PackedDeltasIter = struct {
    data: []const u8 = &.{},
    x_run: RunState = .{},
    y_run: RunState = .{},

    /// A total number of deltas per axis.
    ///
    /// Required only by restart()
    total_count: u16 = 0,

    scalar: f32 = 0.0,

    const RunState = struct {
        data_offset: u16 = 0,
        state: State = .control,
        run_deltas_left: u8 = 0,

        fn next(
            self: *RunState,
            data: []const u8,
            scalar: f32,
        ) ?f32 {
            if (self.state == .control) {
                if (self.data_offset == data.len) return null;

                var s = parser.Stream.new_at(data, self.data_offset) catch return null;
                const control = s.read(Control) catch return null;

                self.data_offset += 1;
                self.run_deltas_left = control.run_count();
                self.state = if (control.deltas_are_zero_flag)
                    .zero_delta
                else if (control.delta_are_words_flag)
                    .long_delta
                else
                    .short_delta;

                return self.next(data, scalar);
            } else {
                var s = parser.Stream.new_at(data, self.data_offset) catch return null;
                const delta: f32 = switch (self.state) {
                    .zero_delta => 0.0,
                    .long_delta => l: {
                        self.data_offset += 2;
                        break :l @as(f32, @floatFromInt(s.read(i16) catch return null)) * scalar;
                    },
                    .short_delta => s: {
                        self.data_offset += 1;
                        break :s @as(f32, @floatFromInt(s.read(i8) catch return null)) * scalar;
                    },
                    else => unreachable,
                };
                self.run_deltas_left -= 1;
                if (self.run_deltas_left == 0) self.state = .control;

                return delta;
            }
        }
    };

    const State = enum {
        control,
        zero_delta,
        short_delta,
        long_delta,
    };

    const Control = packed struct(u8) {
        delta_run_count_mask: u6 = 0,
        delta_are_words_flag: bool = false,
        deltas_are_zero_flag: bool = false,

        // 'Mask for the low 6 bits to provide the number of delta values in the run, minus one.'
        // So we have to add 1.
        // It will never overflow because of a mask.
        fn run_count(
            self: Control,
        ) u8 {
            return self.delta_run_count_mask + 1;
        }
    };

    /// `count` indicates a number of delta pairs.
    pub fn new(
        scalar: f32,
        count: u16,
        data: []const u8,
    ) PackedDeltasIter {
        std.debug.assert(@sizeOf(PackedDeltasIter) <= 32);

        var iter = PackedDeltasIter{
            .data = data,
            .total_count = count,
            .scalar = scalar,
        };

        // 'The packed deltas are arranged with all of the deltas for X coordinates first,
        // followed by the deltas for Y coordinates.'
        // So we have to skip X deltas in the Y deltas iterator.
        //
        // Note that Y deltas doesn't necessarily start with a Control byte
        // and can actually start in the middle of the X run.
        // So we can't simply split the input data in half
        // and process those chunks separately.
        for (0..count) |_| _ = iter.y_run.next(data, scalar);

        return iter;
    }

    pub fn next(
        self: *PackedDeltasIter,
    ) ?struct { f32, f32 } {
        const x = self.x_run.next(self.data, self.scalar) orelse return null;
        const y = self.y_run.next(self.data, self.scalar) orelse return null;
        return .{ x, y };
    }
};

const PointAndDelta = struct {
    x: i16,
    y: i16,
    x_delta: f32,
    y_delta: f32,
};
