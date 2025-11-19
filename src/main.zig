const std = @import("std");
const tetfy = @import("tetfy");

pub fn main() !void {
    const data: []u8 = &.{};

    _ = try tetfy.Face.parse(data, 0);
}
