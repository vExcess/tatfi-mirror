const std = @import("std");
const tetfy = @import("tetfy");

pub fn main() !void {
    defer std.debug.print(
        \\compiled successfully
        \\
    , .{});

    const face = tetfy.Face.parse("true", 0) catch return;
    _ = face.raw_face.table(.{ .inner = 53 }) orelse {};
    _ = face.names();
    _ = face.style();
    _ = face.is_bold();
    _ = face.is_italic();
    _ = face.is_monospaced();
    _ = face.is_oblique();
    _ = face.is_variable();
    _ = face.italic_angle();
    _ = face.is_regular();
    _ = face.weight();
    _ = face.width();

    const raw_tables: tetfy.RawFaceTables = .{};
    _ = tetfy.Face.from_raw_tables(raw_tables) catch {};
}
