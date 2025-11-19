//! A [Horizontal/Vertical Metrics Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx) implementation.

const std = @import("std");
const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;

/// A [Horizontal/Vertical Metrics Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/hmtx).
///
/// `hmtx` and `vmtx` tables has the same structure, so we're reusing the same struct for both.
pub const Table = struct {
    /// A list of metrics indexed by glyph ID.
    metrics: LazyArray16(Metrics),
    /// Side bearings for glyph IDs greater than or equal to the number of `metrics` values.
    bearings: LazyArray16(i16),
    /// Sum of long metrics + bearings.
    number_of_metrics: u16,

    /// Parses a table from raw data.
    ///
    /// - `number_of_metrics` is from the `hhea`/`vhea` table.
    /// - `number_of_glyphs` is from the `maxp` table.
    pub fn parse(
        number_of_metrics_immutable: u16,
        number_of_glyphs: u16, // nonzero
        data: []const u8,
    ) ?Table {
        var number_of_metrics = number_of_metrics_immutable;
        if (number_of_metrics == 0 or
            number_of_glyphs == 0) return null;

        var s = parser.Stream.new(data);
        const metrics = s.read_array(Metrics, number_of_metrics) orelse
            return null;

        // 'If the number_of_metrics is less than the total number of glyphs,
        // then that array is followed by an array for the left side bearing values
        // of the remaining glyphs.'
        const bearings_count = std.math.sub(u16, number_of_glyphs, number_of_metrics);

        const bearings: LazyArray16(i16) = if (bearings_count) |count| b: {
            number_of_metrics += count;
            // Some malformed fonts can skip "left side bearing values"
            // even when they are expected.
            // Therefore if we weren't able to parser them, simply fallback to an empty array.
            // No need to mark the whole table as malformed.
            break :b s.read_array(i16, count) orelse .{};
        } else |_| .{};

        return .{
            .metrics = metrics,
            .bearings = bearings,
            .number_of_metrics = number_of_metrics,
        };
    }
};

/// Horizontal/Vertical Metrics.
pub const Metrics = struct {
    /// Width/Height advance for `hmtx`/`vmtx`.
    advance: u16,
    /// Left/Top side bearing for `hmtx`/`vmtx`.
    side_bearing: i16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(data: *const [SIZE]u8) ?Self {
            var s = parser.Stream.new(data);

            return .{
                .advance = s.read(u16) orelse return null,
                .side_bearing = s.read(i16) orelse return null,
            };
        }
    };
};
