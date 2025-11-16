const parser = @import("../../parser.zig");

const StringId = @import("../cff.zig").StringId;

const LazyArray16 = parser.LazyArray16;

pub const Charset = union(enum) {
    iso_adobe,
    expert,
    expert_subset,
    format0: LazyArray16(StringId),
    format1: LazyArray16(Format1Range),
    format2: LazyArray16(Format2Range),
};

pub const Format1Range = struct {
    first: StringId,
    left: u8,
};

pub const Format2Range = struct {
    first: StringId,
    left: u16,
};
