//! A [Naming Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/name) implementation.

const parser = @import("../parser.zig");

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;

/// A [Naming Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/name).
pub const Table = struct {
    /// A list of names.
    names: Names,
};

/// A list of face names.
pub const Names = struct {
    records: LazyArray16(NameRecord),
    storage: []const u8,
};

const NameRecord = struct {
    platform_id: PlatformId,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    length: u16,
    offset: Offset16,
};

/// A [platform ID](https://docs.microsoft.com/en-us/typography/opentype/spec/name#platform-ids).
pub const PlatformId = enum {
    unicode,
    macintosh,
    iso,
    windows,
    custom,
};
