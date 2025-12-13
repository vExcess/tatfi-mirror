//!
//! A [Character to Glyph Index Mapping Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cmap) implementation.
//!
//! This module provides a low-level alternative to
//! `Face.glyph_index` and
//! `Face.glyph_variation_index`
//! methods.

const parser = @import("../parser.zig");

const PlatformId = @import("name.zig").PlatformId;
const GlyphId = @import("../lib.zig").GlyphId;

const LazyArray16 = parser.LazyArray16;
const Offset32 = parser.Offset32;

pub const Subtable0 = @import("cmap/format0.zig").Subtable0;
pub const Subtable2 = @import("cmap/format2.zig").Subtable2;
pub const Subtable4 = @import("cmap/format4.zig").Subtable4;
pub const Subtable6 = @import("cmap/format6.zig").Subtable6;
pub const Subtable10 = @import("cmap/format10.zig").Subtable10;
pub const Subtable12 = @import("cmap/format12.zig").Subtable12;
pub const Subtable13 = @import("cmap/format13.zig").Subtable13;
pub const Subtable14 = @import("cmap/format14.zig").Subtable14;
pub const GlyphVariationResult = @import("cmap/format14.zig").GlyphVariationResult;

/// A [Character to Glyph Index Mapping Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cmap).
pub const Table = struct {
    /// A list of subtables.
    subtables: Subtables,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        s.skip(u16); // version

        const count = try s.read(u16);
        const records = try s.read_array(EncodingRecord, count);

        return .{
            .subtables = .{
                .data = data,
                .records = records,
            },
        };
    }
};

/// A list of subtables.
pub const Subtables = struct {
    data: []const u8,
    records: LazyArray16(EncodingRecord),

    /// Returns a subtable at an index.
    pub fn get(
        self: Subtables,
        index: u16,
    ) ?Subtable {
        const record = self.records.get(index) orelse return null;
        if (record.offset[0] > self.data.len) return null;
        const data = self.data[record.offset[0]..];

        var s = parser.Stream.new(data);
        const format_int = s.read(u16) catch return null;
        const format: Format = switch (format_int) {
            0 => .{ .byte_encoding_table = Subtable0.parse(data) catch return null },
            2 => .{ .high_byte_mapping_through_table = Subtable2.parse(data) catch return null },
            4 => .{ .segment_mapping_to_delta_values = Subtable4.parse(data) catch return null },
            6 => .{ .trimmed_table_mapping = Subtable6.parse(data) catch return null },
            8 => .mixed_coverage, // unsupported
            10 => .{ .trimmed_array = Subtable10.parse(data) catch return null },
            12 => .{ .segmented_coverage = Subtable12.parse(data) catch return null },
            13 => .{ .many_to_one_range_mappings = Subtable13.parse(data) catch return null },
            14 => .{ .unicode_variation_sequences = Subtable14.parse(data) catch return null },
            else => return null,
        };

        return .{
            .platform_id = record.platform_id,
            .encoding_id = record.encoding_id,
            .format = format,
        };
    }

    /// Returns the number of subtables.
    pub fn len(self: Subtables) u16 {
        return self.records.len();
    }

    pub fn iterator(
        data: *const Subtables,
    ) Iterator {
        return .{ .data = data };
    }

    pub const Iterator = struct {
        data: *const Subtables,
        index: u16 = 0,

        pub fn next(
            self: *Iterator,
        ) ?Subtable {
            if (self.index < self.data.records.len()) {
                defer self.index += 1;
                return self.data.get(self.index);
            } else return null;
        }
    };
};

const EncodingRecord = struct {
    platform_id: PlatformId,
    encoding_id: u16,
    offset: Offset32,

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

/// A character encoding subtable.
pub const Subtable = struct {
    /// Subtable platform.
    platform_id: PlatformId,
    /// Subtable encoding.
    encoding_id: u16,
    /// A subtable format.
    format: Format,

    /// Checks that the current encoding is Unicode compatible.
    pub fn is_unicode(
        self: Subtable,
    ) bool {
        // https://docs.microsoft.com/en-us/typography/opentype/spec/name#windows-encoding-ids
        const WINDOWS_UNICODE_BMP_ENCODING_ID: u16 = 1;
        const WINDOWS_UNICODE_FULL_REPERTOIRE_ENCODING_ID: u16 = 10;

        return switch (self.platform_id) {
            .unicode => true,
            .windows => w: {
                if (self.encoding_id == WINDOWS_UNICODE_BMP_ENCODING_ID) break :w true;

                // "Note: Subtable format 13 has the same structure as format 12; it differs only
                // in the interpretation of the startGlyphID/glyphID fields".
                const is_format_12_compatible =
                    self.format == .segmented_coverage or
                    self.format == .many_to_one_range_mappings;

                // "Fonts that support Unicode supplementary-plane characters (U+10000 to U+10FFFF)
                // on the Windows platform must have a format 12 subtable for platform ID 3,
                // encoding ID 10."
                break :w self.encoding_id == WINDOWS_UNICODE_FULL_REPERTOIRE_ENCODING_ID and
                    is_format_12_compatible;
            },
            else => false,
        };
    }

    /// Maps a character to a glyph ID.
    ///
    /// This is a low-level method and unlike `Face.glyph_index` it doesn't
    /// check that the current encoding is Unicode.
    /// It simply maps a `u32` codepoint number to a glyph ID.
    ///
    /// Returns `null`:
    /// - when glyph ID is `0`.
    /// - when format is `MixedCoverage`, since it's not supported.
    /// - when format is `UnicodeVariationSequences`. Use `glyph_variation_index` instead.
    pub fn glyph_index(
        self: Subtable,
        code_point: u21,
    ) ?GlyphId {
        return switch (self.format) {
            .mixed_coverage => null,
            // This subtable should be accessed via glyph_variation_index().
            .unicode_variation_sequences => null,
            inline else => |subtable| subtable.glyph_index(code_point),
        };
    }

    /// Resolves a variation of a glyph ID from two code points.
    ///
    /// Returns `null`:
    /// - when glyph ID is `0`.
    /// - when format is not `unicode_variation_sequences`.
    pub fn glyph_variation_index(
        self: Subtable,
        code_point: u21,
        variation: u32,
    ) ?GlyphVariationResult {
        switch (self.format) {
            .unicode_variation_sequences,
            => |subtable| return subtable.glyph_index(code_point, variation),
            else => return null,
        }
    }

    /// Calls `f` for all codepoints contained in this subtable.
    ///
    /// This is a low-level method and it doesn't check that the current
    /// encoding is Unicode. It simply calls the function `f` for all `u32`
    /// codepoints that are present in this subtable.
    ///
    /// Note that this may list codepoints for which `glyph_index` still returns
    /// `null` because this method finds all codepoints which were _defined_ in
    /// this subtable. The subtable may still map them to glyph ID `0`.
    ///
    /// Returns without doing anything:
    /// - when format is `MixedCoverage`, since it's not supported.
    /// - when format is `UnicodeVariationSequences`, since it's not supported.
    pub fn codepoints(
        self: Subtable,
        ctx: anytype,
        F: fn (u32, @TypeOf(ctx)) void,
    ) void {
        switch (self.format) {
            .mixed_coverage, .unicode_variation_sequences => {}, // unsupported
            inline else => |subtable| subtable.codepoints(ctx, F),
        }
    }
};

/// A character encoding subtable variant.
pub const Format = union(enum) {
    byte_encoding_table: Subtable0,
    high_byte_mapping_through_table: Subtable2,
    segment_mapping_to_delta_values: Subtable4,
    trimmed_table_mapping: Subtable6,
    mixed_coverage, // unsupported
    trimmed_array: Subtable10,
    segmented_coverage: Subtable12,
    many_to_one_range_mappings: Subtable13,
    unicode_variation_sequences: Subtable14,
};
