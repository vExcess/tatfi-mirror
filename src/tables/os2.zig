//! A [OS/2 and Windows Metrics Table](https://docs.microsoft.com/en-us/typography/opentype/spec/os2)
//! implementation.

const cfg = @import("config");

/// A [OS/2 and Windows Metrics Table](https://docs.microsoft.com/en-us/typography/opentype/spec/os2).
pub const Table = struct {
    /// Table version.
    version: u8,
    data: []const u8,
};
