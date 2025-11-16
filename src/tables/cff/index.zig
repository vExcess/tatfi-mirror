pub const Index = struct {
    data: []const u8,
    offsets: VarOffsets,
};

pub const VarOffsets = struct {
    data: []const u8,
    offset_size: OffsetSize,
};

pub const OffsetSize = enum(u2) {
    size1, // = 1
    size2, // = 2
    size3, // = 3
    size4, // = 4
};
