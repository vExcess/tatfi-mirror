const std = @import("std");
const tetfy = @import("tetfy");

pub fn main() !void {
    defer std.debug.print(
        \\compiled successfully
        \\
    , .{});

    _ = tetfy.Face.parse("true", 0) catch {};

    const raw_tables: tetfy.RawFaceTables = .{};
    _ = tetfy.Face.from_raw_tables(raw_tables) catch {};
}
