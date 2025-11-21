//!
//! A [Kerning Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/kern) implementation.
//!
//! Supports both
//! [OpenType](https://docs.microsoft.com/en-us/typography/opentype/spec/kern)
//! and
//! [Apple Advanced Typography](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6kern.html)
//! variants.
//!
//! Since there is no single correct way to process a kerning data,
//! we have to provide an access to kerning subtables, so a caller can implement
//! a kerning algorithm manually.
//! But we still try to keep the API as high-level as possible.

const parser = @import("../parser.zig");

const GlyphId = @import("../lib.zig").GlyphId;

/// A [Kerning Table](https://docs.microsoft.com/en-us/typography/opentype/spec/kern).
pub const Table = struct {
    /// A list of subtables.
    subtables: Subtables,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        // The `kern` table has two variants: OpenType and Apple.
        // And they both have different headers.
        // There are no robust way to distinguish them, so we have to guess.
        //
        // The OpenType one has the first two bytes (UInt16) as a version set to 0.
        // While Apple one has the first four bytes (Fixed) set to 1.0
        // So the first two bytes in case of an OpenType format will be 0x0000
        // and 0x0001 in case of an Apple format.
        var s = parser.Stream.new(data);

        const version = try s.read(u16);

        const subtables: Subtables = if (version == 0) .{
            .is_aat = false,
            .count = try s.read(u16),
            .data = try s.tail(),
        } else e: {
            s.skip(u16); // Skip the second part of u32 version.
            // Note that AAT stores the number of tables as u32 and not as u16.
            break :e .{
                .is_aat = true,
                .count = try s.read(u32),
                .data = try s.tail(),
            };
        };

        return .{ .subtables = subtables };
    }
};

/// A list of subtables.
///
/// The internal data layout is not designed for random access,
/// therefore we're not providing the `get()` method and only an iterator.
pub const Subtables = struct {
    /// Indicates an Apple Advanced Typography format.
    is_aat: bool,
    /// The total number of tables.
    count: u32,
    /// Actual data. Starts right after the `kern` header.
    data: []const u8,
};
