const parser = @import("../../parser.zig");

const StringId = @import("../cff.zig").StringId;

const LazyArray16 = parser.LazyArray16;

pub const Encoding = struct {
    kind: EncodingKind,
    supplemental: LazyArray16(Supplement),
};

pub const EncodingKind = union(enum) {
    standard,
    expert,
    format0: LazyArray16(u8),
    format1: LazyArray16(Format1Range),
};

pub const Supplement = struct {
    code: u8,
    name: StringId,
};

pub const Format1Range = struct {
    first: u8,
    left: u8,
};
