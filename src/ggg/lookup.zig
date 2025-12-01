const parser = @import("../parser.zig");

const gpos = @import("../tables/gpos.zig");
const gsub = @import("../tables/gsub.zig");

/// A list of [`Lookup`] values.
pub const LookupList = parser.LazyOffsetArray16(Lookup);

/// A [Lookup Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#lookup-table).
pub const Lookup = struct {
    /// Lookup qualifiers.
    flags: LookupFlags,
    /// Available subtables.
    subtables: LookupSubtables,
    /// Index into GDEF mark glyph sets structure.
    mark_filtering_set: ?u16,

    pub fn parse(
        data: []const u8,
    ) parser.Error!Lookup {
        var s = parser.Stream.new(data);
        const kind = try s.read(u16);
        const flags = try s.read(LookupFlags);
        const count = try s.read(u16);
        const offsets = try s.read_array(parser.Offset16, count);

        var mark_filtering_set: ?u16 = null;
        if (flags.use_mark_filtering_set) {
            mark_filtering_set = try s.read(u16);
        }

        return .{
            .flags = flags,
            .subtables = .{
                .kind = kind,
                .data = data,
                .offsets = offsets,
            },
            .mark_filtering_set = mark_filtering_set,
        };
    }
};

/// Lookup table flags.
pub const LookupFlags = packed struct(u16) {
    right_to_left: bool,
    ignore_base_glyphs: bool,
    ignore_ligatures: bool,
    ignore_marks: bool,
    use_mark_filtering_set: bool,
    _0: u3 = 0,
    mark_attachment_type: u8,

    pub fn ignore_flags(self: LookupFlags) bool {
        //  self & 0x000E != 0
        return self.ignore_base_glyphs or
            self.ignore_ligatures or
            self.ignore_marks;
    }
};

/// A list of lookup subtables.
pub const LookupSubtables = struct {
    kind: u16,
    data: []const u8,
    offsets: parser.LazyArray16(parser.Offset16),

    /// Returns a number of items in the LookupSubtables.
    pub fn len(
        self: LookupSubtables,
    ) u16 {
        return self.offsets.len();
    }

    /// Parses a subtable at index.
    ///
    /// Accepts either `gpos.PositioningSubtable` or `gsub.SubstitutionSubtable`
    pub fn get(
        self: LookupSubtables,
        T: type,
        index: u16,
    ) ?T {
        if (T != gpos.PositioningSubtable and T != gsub.SubstitutionSubtable)
            @compileError("LookupSubtables only accepts gpos.PositioningSubtable or gsub.SubstitutionSubtable");

        const offset = self.offsets.get(index) orelse return null;
        if (offset[0] > self.data.len) return null;
        const data = self.data[offset[0]..];
        return T.parse(data, self.kind) catch null;
    }

    pub fn iterator(
        data: *const LookupSubtables,
        T: type,
    ) Iterator(T) {
        return .{ .data = data };
    }

    pub fn Iterator(T: type) type {
        return struct {
            data: *const LookupSubtables,
            index: u16 = 0,

            const Self = @This();

            pub fn next(
                self: *Self,
            ) ?T {
                if (self.index < self.data.len()) {
                    defer self.index += 1;
                    return self.data.get(T, self.index);
                } else {
                    return null;
                }
            }
        };
    }
};

pub fn parse_extension_lookup(
    T: type,
    data: []const u8,
) parser.Error!T {
    var s = parser.Stream.new(data);
    if (try s.read(u16) != 1) return error.ParseFail;

    const kind = try s.read(u16);
    const offset = try s.read(parser.Offset32);
    if (offset[0] > data.len) return error.ParseFail;

    return T.parse(data[offset[0]..], kind);
}
