const std = @import("std");
const tetfy = @import("tetfy");

pub fn main() !void {
    // const data: []const u8 = &.{ 0x74, 0x72, 0x75, 0x65 };

    _ = tetfy.Face.parse("true", 0) catch |e| std.debug.print(
        \\compiled successfully
        \\returned {t}
        \\
    , .{e});
}
