//! A [OS/2 and Windows Metrics Table](https://docs.microsoft.com/en-us/typography/opentype/spec/os2)
//! implementation.

const parser = @import("../parser.zig");

/// A [OS/2 and Windows Metrics Table](https://docs.microsoft.com/en-us/typography/opentype/spec/os2).
pub const Table = struct {
    /// Table version.
    version: u8,
    data: []const u8,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        const version = try s.read(u16);

        const table_len: usize = switch (version) {
            0 => 78,
            1 => 86,
            2 => 96,
            3 => 96,
            4 => 96,
            5 => 100,
            else => return error.ParseFail,
        };

        // Do not check the exact length, because some fonts include
        // padding in table's length in table records, which is incorrect.
        if (data.len < table_len) return error.ParseFail;

        return .{
            .version = @truncate(version),
            .data = data,
        };
    }
};
