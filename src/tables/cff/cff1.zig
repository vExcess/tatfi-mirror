//! A [Compact Font Format Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cff) implementation.

// Useful links:
// http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/font/pdfs/5176.CFF.pdf
// http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/font/pdfs/5177.Type2.pdf
// https://github.com/opentypejs/opentype.js/blob/master/src/tables/cff.js

const std = @import("std");
const lib = @import("../../lib.zig");
const utils = @import("../../utils.zig");
const parser = @import("../../parser.zig");
const cff = @import("../cff.zig");

const Encoding = @import("encoding.zig");
const Index = @import("index.zig");
const Charset = @import("charset.zig").Charset;
const DictionaryParser = @import("dict.zig");
const CharStringParser = @import("charstring.zig");

const LazyArray16 = parser.LazyArray16;

// Limits according to the Adobe Technical Note #5177 Appendix B.
const STACK_LIMIT: u8 = 10;
const MAX_ARGUMENTS_STACK_LEN: usize = 48;

const TWO_BYTE_OPERATOR_MARK: u8 = 12;

/// Enumerates Charset IDs defined in the Adobe Technical Note #5176, Table 22
const charset_id = struct {
    pub const ISO_ADOBE: usize = 0;
    pub const EXPERT: usize = 1;
    pub const EXPERT_SUBSET: usize = 2;
};

/// Enumerates Charset IDs defined in the Adobe Technical Note #5176, Table 16
const encoding_id = struct {
    pub const STANDARD: usize = 0;
    pub const EXPERT: usize = 1;
};

/// Enumerates some operators defined in the Adobe Technical Note #5176,
/// Table 23 Private DICT Operators
const private_dict_operator = struct {
    pub const LOCAL_SUBROUTINES_OFFSET: u16 = 19;
    pub const DEFAULT_WIDTH: u16 = 20;
    pub const NOMINAL_WIDTH: u16 = 21;
};

/// Enumerates some operators defined in the Adobe Technical Note #5177.
const adobe_operator = struct {
    pub const HORIZONTAL_STEM: u8 = 1;
    pub const VERTICAL_STEM: u8 = 3;
    pub const VERTICAL_MOVE_TO: u8 = 4;
    pub const LINE_TO: u8 = 5;
    pub const HORIZONTAL_LINE_TO: u8 = 6;
    pub const VERTICAL_LINE_TO: u8 = 7;
    pub const CURVE_TO: u8 = 8;
    pub const CALL_LOCAL_SUBROUTINE: u8 = 10;
    pub const RETURN: u8 = 11;
    pub const ENDCHAR: u8 = 14;
    pub const HORIZONTAL_STEM_HINT_MASK: u8 = 18;
    pub const HINT_MASK: u8 = 19;
    pub const COUNTER_MASK: u8 = 20;
    pub const MOVE_TO: u8 = 21;
    pub const HORIZONTAL_MOVE_TO: u8 = 22;
    pub const VERTICAL_STEM_HINT_MASK: u8 = 23;
    pub const CURVE_LINE: u8 = 24;
    pub const LINE_CURVE: u8 = 25;
    pub const VV_CURVE_TO: u8 = 26;
    pub const HH_CURVE_TO: u8 = 27;
    pub const SHORT_INT: u8 = 28;
    pub const CALL_GLOBAL_SUBROUTINE: u8 = 29;
    pub const VH_CURVE_TO: u8 = 30;
    pub const HV_CURVE_TO: u8 = 31;
    pub const HFLEX: u8 = 34;
    pub const FLEX: u8 = 35;
    pub const HFLEX1: u8 = 36;
    pub const FLEX1: u8 = 37;
    pub const FIXED_16_16: u8 = 255;
};

/// A [Compact Font Format Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cff).
pub const Table = struct {
    // The whole CFF table.
    // Used to resolve a local subroutine in a CID font.
    table_data: []const u8,

    strings: Index,
    global_subrs: Index,
    charset: Charset,
    number_of_glyphs: u16, // nonzero
    matrix: Matrix,
    char_strings: Index,
    kind: FontKind,

    // Copy of Face.units_per_em().
    // Required to do glyph outlining, since coordinates must be scaled up by this before applying the `matrix`.
    units_per_em: ?u16,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        return try Table.parse_inner(data, null);
    }

    /// The same as `Table.parse`, with the difference that it allows you to
    /// manually pass the units per em of the font, which is needed to properly
    /// scale certain fonts with a non-identity matrix.
    pub fn parse_with_upem(
        data: []const u8,
        units_per_em: u16,
    ) parser.Error!Table {
        return try Table.parse_inner(data, units_per_em);
    }

    fn parse_inner(
        data: []const u8,
        units_per_em: ?u16,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        // Parse Header.
        const major = try s.read(u8);
        s.skip(u8); // minor
        const header_size = try s.read(u8);
        s.skip(u8); // Absolute offset

        if (major != 1) return error.ParseFail;

        // Jump to Name INDEX. It's not necessarily right after the header.
        if (header_size > 4) s.advance(header_size - 4);

        // Skip Name INDEX.
        try Index.skip(u16, &s);

        const top_dict = try parse_top_dict(&s);

        // Must be set, otherwise there are nothing to parse.
        if (top_dict.char_strings_offset == 0) return error.ParseFail;

        // String INDEX.
        const strings = try Index.parse(u16, &s);

        // Parse Global Subroutines INDEX.
        const global_subrs = try Index.parse(u16, &s);

        const char_strings = cs: {
            var scs = try parser.Stream.new_at(data, top_dict.char_strings_offset);
            break :cs try Index.parse(u16, &scs);
        };

        // 'The number of glyphs is the value of the count field in the CharStrings INDEX.'
        const number_of_glyphs = std.math.cast(u16, char_strings.len()) orelse
            return error.ParseFail;
        if (number_of_glyphs == 0) return error.ParseFail;

        // continue from line 941 in cff1.rs
        const charset: Charset = if (top_dict.charset_offset) |charset_offset|
            switch (charset_offset) {
                charset_id.ISO_ADOBE => .iso_adobe,
                charset_id.EXPERT => .expert,
                charset_id.EXPERT_SUBSET => .expert_subset,
                else => s: {
                    var sco = try parser.Stream.new_at(data, charset_offset);
                    break :s try Charset.parse_charset(number_of_glyphs, &sco);
                },
            }
        else
            .iso_adobe; // default

        const matrix = top_dict.matrix;

        const kind = if (top_dict.has_ros)
            try parse_cid_metadata(data, top_dict, number_of_glyphs)
        else k: {
            // Only SID fonts are allowed to have an Encoding.
            const encoding: Encoding = if (top_dict.encoding_offset) |offset|
                switch (offset) {
                    encoding_id.STANDARD => .new_standard,
                    encoding_id.EXPERT => .new_expert,
                    else => e: {
                        var se = try parser.Stream.new_at(data, offset);
                        break :e try .parse(&se);
                    },
                }
            else
                .new_standard;

            break :k try parse_sid_metadata(data, top_dict, encoding);
        };

        return .{
            .table_data = data,
            .strings = strings,
            .global_subrs = global_subrs,
            .charset = charset,
            .number_of_glyphs = number_of_glyphs,
            .matrix = matrix,
            .char_strings = char_strings,
            .kind = kind,
            .units_per_em = units_per_em,
        };
    }

    /// Resolves a Glyph ID for a code point.
    ///
    /// Similar to `Face.glyph_index` but 8bit
    /// and uses CFF encoding and charset tables instead of TrueType `cmap`.
    pub fn glyph_index(
        self: Table,
        code_point: u8,
    ) ?lib.GlyphId {
        if (self.kind == .cid) return null;

        return self.kind.sid.encoding.code_to_gid(self.charset, code_point) orelse
            // Try using the Standard encoding otherwise.
            // Custom Encodings does not guarantee to include all glyphs.
            Encoding.new_standard.code_to_gid(self.charset, code_point);
    }

    /// Returns a glyph width.
    ///
    /// This value is different from outline bbox width and is stored separately.
    ///
    /// Technically similar to `Face.glyph_hor_advance`.
    pub fn glyph_width(
        self: Table,
        glyph_id: lib.GlyphId,
    ) ?u16 {
        if (self.kind == .cid) return null;

        const sid = self.kind.sid;
        const data = self.char_strings.get(glyph_id[0]) orelse return null;
        _, const maybe_width = parse_char_string(
            data,
            &self,
            glyph_id,
            true,
            lib.OutlineBuilder.dummy_builder,
        ) catch return null;
        const width = w: {
            const w = maybe_width orelse break :w sid.default_width;
            break :w sid.nominal_width + w;
        };

        return utils.f32_to_u16(width);
    }

    /// Returns a glyph ID by a name.
    pub fn glyph_index_by_name(
        self: Table,
        name: []const u8,
    ) ?lib.GlyphId {
        if (self.kind == .cid) return null;

        const sid: cff.StringId = sid: for (cff.STANDARD_NAMES, 0..) |n, pos| {
            if (std.mem.eql(u8, n, name)) break :sid .{@truncate(pos)};
        } else {
            var iter = self.strings.iterator();
            var pos: usize = 0;

            const index = while (iter.next()) |n| : (pos += 1) {
                if (std.mem.eql(u8, n, name)) break pos;
            } else return null;
            break :sid .{@truncate(index + cff.STANDARD_NAMES.len)};
        };

        return self.charset.sid_to_gid(sid);
    }

    /// Returns a glyph name.
    pub fn glyph_name(
        self: Table,
        glyph_id: lib.GlyphId,
    ) ?[]const u8 {
        if (self.kind == .cid) return null;

        const sid = self.charset.gid_to_sid(glyph_id) orelse return null;

        if (sid[0] < cff.STANDARD_NAMES.len) return cff.STANDARD_NAMES[sid[0]];

        const index = std.math.cast(u32, sid[0] - cff.STANDARD_NAMES.len) orelse return null;
        return self.strings.get(index);
    }

    /// Outlines a glyph.
    pub fn outline(
        self: Table,
        glyph_id: lib.GlyphId,
        builder: lib.OutlineBuilder,
    ) cff.Error!lib.Rect {
        const data = self.char_strings.get(glyph_id[0]) orelse return error.NoGlyph;
        const ret = try parse_char_string(data, &self, glyph_id, false, builder);
        return ret[0];
    }

    /// Returns the CID corresponding to a glyph ID.
    ///
    /// Returns `null` if this is not a CIDFont.
    pub fn glyph_cid(
        self: Table,
        glyph_id: lib.GlyphId,
    ) ?u16 {
        if (self.kind == .sid) return null;

        const ret = self.charset.gid_to_sid(glyph_id) orelse return null;
        return ret[0];
    }
};

/// An affine transformation matrix.
//[ARS] I dont know what affine means here
pub const Matrix = struct {
    sx: f32 = 0,
    ky: f32 = 0,
    kx: f32 = 0,
    sy: f32 = 0.001,
    tx: f32 = 0,
    ty: f32 = 0,
};

pub const FontKind = union(enum) {
    sid: SIDMetadata,
    cid: CIDMetadata,
};

pub const SIDMetadata = struct {
    local_subrs: Index = .default,
    /// Can be zero.
    default_width: f32 = 0.0,
    /// Can be zero.
    nominal_width: f32 = 0.0,
    encoding: Encoding = .new_standard,
};

pub const CIDMetadata = struct {
    fd_array: Index = .default,
    fd_select: FDSelect = .{ .format0 = .{} },
};

pub const FDSelect = union(enum) {
    format0: LazyArray16(u8),
    format3: []const u8, // It's easier to parse it in-place.

    fn font_dict_index(
        self: FDSelect,
        glyph_id: lib.GlyphId,
    ) parser.Error!u8 {
        switch (self) {
            .format0 => |array| return array.get(glyph_id[0]) orelse error.ParseFail,
            .format3 => |data| {
                var s = parser.Stream.new(data);

                const number_of_ranges = try s.read(u16);
                if (number_of_ranges == 0) return error.ParseFail;

                // 'A sentinel GID follows the last range element and serves
                // to delimit the last range in the array.'

                // Range is: GlyphId + u8
                var prev_first_glyph = try s.read(lib.GlyphId);
                var prev_index = try s.read(u8);
                for (0..number_of_ranges) |_| {
                    const curr_first_glyph = try s.read(lib.GlyphId);

                    if (glyph_id[0] >= prev_first_glyph[0] and
                        glyph_id[0] < curr_first_glyph[0])
                        return prev_index
                    else
                        prev_index = try s.read(u8);

                    prev_first_glyph = curr_first_glyph;
                }

                return error.ParseFail;
            },
        }
    }
};

const TopDict = struct {
    charset_offset: ?usize = null,
    encoding_offset: ?usize = null,
    char_strings_offset: usize = 0,
    /// start , length
    private_dict_range: ?struct { usize, usize } = null,
    matrix: Matrix = .{},
    has_ros: bool = false,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
};

// Limits according to the Adobe Technical Note #5176, chapter 4 DICT Data.
const MAX_OPERANDS_LEN: usize = 48;

/// Enumerates some operators defined in the Adobe Technical Note #5176,
/// Table 9 Top DICT Operator Entries
const top_dict_operator = struct {
    pub const CHARSET_OFFSET: u16 = 15;
    pub const ENCODING_OFFSET: u16 = 16;
    pub const CHAR_STRINGS_OFFSET: u16 = 17;
    pub const PRIVATE_DICT_SIZE_AND_OFFSET: u16 = 18;
    pub const FONT_MATRIX: u16 = 1207;
    pub const ROS: u16 = 1230;
    pub const FD_ARRAY: u16 = 1236;
    pub const FD_SELECT: u16 = 1237;
};

fn parse_top_dict(
    s: *parser.Stream,
) parser.Error!TopDict {
    var top_dict: TopDict = .{};

    const index = try Index.parse(u16, s);
    if (index.data.len == 0) return error.ParseFail;

    // The Top DICT INDEX should have only one dictionary.
    const data = index.get(0) orelse return error.ParseFail;

    var operands_buffer: [MAX_OPERANDS_LEN]f64 = @splat(0.0);
    var dict_parser: DictionaryParser = .new(data, &operands_buffer);

    while (dict_parser.parse_next()) |operator| {
        switch (operator[0]) {
            top_dict_operator.CHARSET_OFFSET => {
                top_dict.charset_offset = dict_parser.parse_offset() catch null;
            },
            top_dict_operator.ENCODING_OFFSET => {
                top_dict.encoding_offset = dict_parser.parse_offset() catch null;
            },
            top_dict_operator.CHAR_STRINGS_OFFSET => {
                top_dict.char_strings_offset = try dict_parser.parse_offset();
            },
            top_dict_operator.PRIVATE_DICT_SIZE_AND_OFFSET => {
                top_dict.private_dict_range = dict_parser.parse_range() catch null;
            },
            top_dict_operator.FONT_MATRIX => {
                try dict_parser.parse_operands();
                const operands = dict_parser.operands_slice();
                if (operands.len == 6) top_dict.matrix = .{
                    .sx = @floatCast(operands[0]),
                    .ky = @floatCast(operands[1]),
                    .kx = @floatCast(operands[2]),
                    .sy = @floatCast(operands[3]),
                    .tx = @floatCast(operands[4]),
                    .ty = @floatCast(operands[5]),
                };
            },
            top_dict_operator.ROS => top_dict.has_ros = true,
            top_dict_operator.FD_ARRAY => {
                top_dict.fd_array_offset = dict_parser.parse_offset() catch null;
            },
            top_dict_operator.FD_SELECT => {
                top_dict.fd_select_offset = dict_parser.parse_offset() catch null;
            },
            else => {},
        }
    }

    return top_dict;
}

fn parse_cid_metadata(
    data: []const u8,
    top_dict: TopDict,
    number_of_glyphs: u16,
) parser.Error!FontKind {
    // charset, FDArray and FDSelect must be set.
    const charset_offset = top_dict.charset_offset orelse return error.ParseFail;
    const fd_array_offset = top_dict.fd_array_offset orelse return error.ParseFail;
    const fd_select_offset = top_dict.fd_select_offset orelse return error.ParseFail;

    if (charset_offset <= charset_id.EXPERT_SUBSET) {
        // 'There are no predefined charsets for CID fonts.'
        // Adobe Technical Note #5176, chapter 18 CID-keyed Fonts
        return error.ParseFail;
    }

    var metadata: CIDMetadata = .{};

    metadata.fd_array = m: {
        var s = try parser.Stream.new_at(data, fd_array_offset);
        break :m try Index.parse(u16, &s);
    };

    metadata.fd_select = f: {
        var s = try parser.Stream.new_at(data, fd_select_offset);
        break :f try parse_fd_select(number_of_glyphs, &s);
    };

    return .{ .cid = metadata };
}

fn parse_fd_select(
    number_of_glyphs: u16,
    s: *parser.Stream,
) parser.Error!FDSelect {
    const format = try s.read(u8);
    return switch (format) {
        0 => .{ .format0 = try s.read_array(u8, number_of_glyphs) },
        3 => .{ .format3 = try s.tail() },
        else => error.ParseFail,
    };
}

fn parse_sid_metadata(
    data: []const u8,
    top_dict: TopDict,
    encoding: Encoding,
) parser.Error!FontKind {
    var metadata: SIDMetadata = .{};
    metadata.encoding = encoding;

    const private_dict_range = top_dict.private_dict_range orelse
        return .{ .sid = metadata };

    const private_dict: PrivateDict = d: {
        const start, const length = private_dict_range;
        break :d parse_private_dict(try utils.slice(data, .{ start, length }));
    };

    metadata.default_width = private_dict.default_width orelse 0.0;
    metadata.nominal_width = private_dict.nominal_width orelse 0.0;

    if (private_dict.local_subroutines_offset) |subroutines_offset|
        // 'The local subroutines offset is relative to the beginning
        // of the Private DICT data.'
        if (std.math.add(usize, private_dict_range[0], subroutines_offset)) |start| {
            var s = parser.Stream.new(try utils.slice(data, start));
            metadata.local_subrs = try Index.parse(u16, &s);
        } else |_| {};

    return .{ .sid = metadata };
}

fn parse_private_dict(
    data: []const u8,
) PrivateDict {
    var dict: PrivateDict = .{};
    var operands_buffer: [MAX_OPERANDS_LEN]f64 = @splat(0.0);
    var dict_parser: DictionaryParser = .new(data, &operands_buffer);

    while (dict_parser.parse_next()) |operator| switch (operator[0]) {
        private_dict_operator.LOCAL_SUBROUTINES_OFFSET => dict.local_subroutines_offset =
            dict_parser.parse_offset() catch null,

        private_dict_operator.DEFAULT_WIDTH => dict.default_width =
            dict_parser.parse_number_method(f32) catch null,

        private_dict_operator.NOMINAL_WIDTH => dict.nominal_width =
            dict_parser.parse_number_method(f32) catch null,

        else => {},
    };

    return dict;
}

const PrivateDict = struct {
    local_subroutines_offset: ?usize = null,
    default_width: ?f32 = null,
    nominal_width: ?f32 = null,
};

const CharStringParserContext = struct {
    metadata: *const Table,
    width: ?f32 = null,
    stems_len: u32 = 0,
    has_endchar: bool = false,
    has_seac: bool = false,
    glyph_id: lib.GlyphId, // Required to parse local subroutine in CID fonts.
    local_subrs: ?Index,
};

fn parse_char_string(
    data: []const u8,
    metadata: *const Table,
    glyph_id: lib.GlyphId,
    width_only: bool,
    builder: lib.OutlineBuilder,
) cff.Error!struct { lib.Rect, ?f32 } {
    const local_subrs = switch (metadata.kind) {
        .sid => |sid| sid.local_subrs,
        .cid => null, // Will be resolved on request.
    };

    var ctx: CharStringParserContext = .{
        .metadata = metadata,
        .glyph_id = glyph_id,
        .local_subrs = local_subrs,
    };

    const transform = t: {
        const upem = metadata.units_per_em orelse break :t null;
        const transform = metadata.matrix;

        break :t if (!std.meta.eql(
            .{ upem, transform },
            .{ 1000, Matrix{} },
        )) .{ upem, transform } else null;
    };

    var inner_builder: cff.Builder = .{
        .builder = builder,
        .bbox = .{},
        .transform_tuple = transform,
    };

    var buffer: [MAX_ARGUMENTS_STACK_LEN]f32 = undefined;
    var cs_parser = CharStringParser{
        .stack = .initBuffer(&buffer),
        .builder = &inner_builder,
        .x = 0.0,
        .y = 0.0,
        .has_move_to = false,
        .is_first_move_to = true,
        .width_only = width_only,
    };

    try parse_char_string_recursive(&ctx, data, 0, &cs_parser);

    if (width_only) return .{ lib.Rect.zero, ctx.width };
    if (!ctx.has_endchar) return error.MissingEndChar;

    const bbox = cs_parser.builder.bbox;
    // Check that bbox was changed.
    if (bbox.is_default()) return error.ZeroBBox;

    const rect = bbox.to_rect() orelse return error.BboxOverflow;
    return .{ rect, ctx.width };
}

fn parse_char_string_recursive(
    ctx: *CharStringParserContext,
    char_string: []const u8,
    depth: u8,
    p: *CharStringParser,
) cff.Error!void {
    var s = parser.Stream.new(char_string);
    while (!s.at_end()) {
        const op = s.read(u8) catch return error.ReadOutOfBounds;
        switch (op) {
            // Reserved.
            0, 2, 9, 13, 15, 16, 17 => return error.InvalidOperator,
            adobe_operator.HORIZONTAL_STEM,
            adobe_operator.VERTICAL_STEM,
            adobe_operator.HORIZONTAL_STEM_HINT_MASK,
            adobe_operator.VERTICAL_STEM_HINT_MASK,
            => {
                // y dy {dya dyb}* hstem
                // x dx {dxa dxb}* vstem
                // y dy {dya dyb}* hstemhm
                // x dx {dxa dxb}* vstemhm

                // If the stack length is uneven, than the first value is a `width`.
                const len = if (p.stack.items.len & 1 != 0 and ctx.width == null) l: {
                    ctx.width = p.stack.items[0];
                    break :l p.stack.items.len - 1;
                } else p.stack.items.len;

                ctx.stems_len += @as(u32, @truncate(len)) >> 1;

                // We are ignoring the hint operators.
                p.stack.clearRetainingCapacity();
            },
            adobe_operator.VERTICAL_MOVE_TO => {
                var i: usize = 0;
                if (p.stack.items.len == 2) {
                    i += 1;
                    if (ctx.width == null) ctx.width = p.stack.items[0];
                }

                try p.parse_vertical_move_to(i);
            },
            adobe_operator.LINE_TO => try p.parse_line_to(),
            adobe_operator.HORIZONTAL_LINE_TO => try p.parse_horizontal_line_to(),
            adobe_operator.VERTICAL_LINE_TO => try p.parse_vertical_line_to(),
            adobe_operator.CURVE_TO => try p.parse_curve_to(),
            adobe_operator.CALL_LOCAL_SUBROUTINE => {
                if (p.stack.items.len == 0) return error.InvalidArgumentsStackLength;
                if (depth == STACK_LIMIT) return error.NestingLimitReached;

                // Parse and remember the local subroutine for the current glyph.
                // Since it's a pretty complex task, we're doing it only when
                // a local subroutine is actually requested by the glyphs charstring.
                if (ctx.local_subrs == null) {
                    if (ctx.metadata.kind == .cid) {
                        const cid = &ctx.metadata.kind.cid;
                        ctx.local_subrs = parse_cid_local_subrs(
                            ctx.metadata.table_data,
                            ctx.glyph_id,
                            cid,
                        ) catch null;
                    }
                }

                if (ctx.local_subrs) |local_subrs| {
                    const subroutine_bias = cff.calc_subroutine_bias(local_subrs.len());
                    const index = try cff.conv_subroutine_index(
                        p.stack.pop() orelse unreachable, // checked stack is not empty
                        subroutine_bias,
                    );

                    const local_char_string = local_subrs.get(index) orelse
                        return error.InvalidSubroutineIndex;

                    try parse_char_string_recursive(ctx, local_char_string, depth + 1, p);
                } else return error.NoLocalSubroutines;

                if (ctx.has_endchar and !ctx.has_seac) {
                    if (!s.at_end()) return error.DataAfterEndChar;
                    break;
                }
            },
            adobe_operator.RETURN => break,
            TWO_BYTE_OPERATOR_MARK => {
                // flex
                const op2 = s.read(u8) catch return error.ReadOutOfBounds;
                switch (op2) {
                    adobe_operator.HFLEX => try p.parse_hflex(),
                    adobe_operator.FLEX => try p.parse_flex(),
                    adobe_operator.HFLEX1 => try p.parse_hflex1(),
                    adobe_operator.FLEX1 => try p.parse_flex1(),
                    else => return error.UnsupportedOperator,
                }
            },
            adobe_operator.ENDCHAR => {
                if (p.stack.items.len == 4 or
                    (ctx.width == null and p.stack.items.len == 5))
                {
                    // Process 'seac'.
                    const accent_char = seac_code_to_glyph_id(
                        ctx.metadata.charset,
                        p.stack.pop() orelse unreachable,
                    ) orelse return error.InvalidSeacCode;

                    const base_char = seac_code_to_glyph_id(
                        ctx.metadata.charset,
                        p.stack.pop() orelse unreachable,
                    ) orelse return error.InvalidSeacCode;

                    const dy = p.stack.pop() orelse unreachable;
                    const dx = p.stack.pop() orelse unreachable; // checked earlier length is at least 4

                    if (ctx.width == null and
                        p.stack.items.len != 0) ctx.width = p.stack.pop();

                    ctx.has_seac = true;

                    if (depth == STACK_LIMIT) return error.NestingLimitReached;

                    const base_char_string = ctx
                        .metadata
                        .char_strings
                        .get(base_char[0]) orelse return error.InvalidSeacCode;

                    try parse_char_string_recursive(ctx, base_char_string, depth + 1, p);

                    p.x = dx;
                    p.y = dy;

                    const accent_char_string = ctx
                        .metadata
                        .char_strings
                        .get(accent_char[0]) orelse return error.InvalidSeacCode;

                    try parse_char_string_recursive(ctx, accent_char_string, depth + 1, p);
                } else if (p.stack.items.len == 1 and ctx.width == null)
                    ctx.width = p.stack.pop();

                if (!p.is_first_move_to) {
                    p.is_first_move_to = true;
                    p.builder.close();
                }
                if (!s.at_end()) return error.DataAfterEndChar;
                ctx.has_endchar = true;

                break;
            },
            adobe_operator.HINT_MASK, adobe_operator.COUNTER_MASK => {
                var len = p.stack.items.len;

                // We are ignoring the hint operators.
                p.stack.clearRetainingCapacity();

                // If the stack length is uneven, than the first value is a `width`.
                if (len & 1 != 0) {
                    len -= 1;
                    if (ctx.width == null) ctx.width = p.stack.items[0];
                }
                ctx.stems_len += @as(u32, @truncate(len)) >> 1;
                s.advance((ctx.stems_len + 7) >> 3);
            },
            adobe_operator.MOVE_TO => {
                const i: usize = if (p.stack.items.len == 3) i: {
                    if (ctx.width == null) ctx.width = p.stack.items[0];
                    break :i 1;
                } else 0;

                try p.parse_move_to(i);
            },
            adobe_operator.HORIZONTAL_MOVE_TO => {
                const i: usize = if (p.stack.items.len == 2) i: {
                    if (ctx.width == null) ctx.width = p.stack.items[0];
                    break :i 1;
                } else 0;

                try p.parse_horizontal_move_to(i);
            },
            adobe_operator.CURVE_LINE => try p.parse_curve_line(),
            adobe_operator.LINE_CURVE => try p.parse_line_curve(),
            adobe_operator.VV_CURVE_TO => try p.parse_vv_curve_to(),
            adobe_operator.HH_CURVE_TO => try p.parse_hh_curve_to(),
            adobe_operator.SHORT_INT => {
                const n = s.read(i16) catch return error.ReadOutOfBounds;
                p.stack.appendBounded(@floatFromInt(n)) catch return error.ArgumentsStackLimitReached;
            },
            adobe_operator.CALL_GLOBAL_SUBROUTINE => {
                if (p.stack.items.len == 0) return error.InvalidArgumentsStackLength;
                if (depth == STACK_LIMIT) return error.NestingLimitReached;

                const subroutine_bias = cff.calc_subroutine_bias(ctx.metadata.global_subrs.len());
                const index = try cff.conv_subroutine_index(
                    p.stack.pop() orelse unreachable,
                    subroutine_bias,
                );
                const sub_char_string = ctx
                    .metadata
                    .global_subrs
                    .get(index) orelse return error.InvalidSubroutineIndex;

                try parse_char_string_recursive(ctx, sub_char_string, depth + 1, p);

                if (ctx.has_endchar and !ctx.has_seac) {
                    if (!s.at_end()) return error.DataAfterEndChar;
                    break;
                }
            },
            adobe_operator.VH_CURVE_TO => try p.parse_vh_curve_to(),
            adobe_operator.HV_CURVE_TO => try p.parse_hv_curve_to(),
            32...246 => try p.parse_int1(op),
            247...250 => try p.parse_int2(op, &s),
            251...254 => try p.parse_int3(op, &s),
            adobe_operator.FIXED_16_16 => try p.parse_fixed(&s),
        }

        if (p.width_only and ctx.width != null) break;
    }

    // [RazrFalcon]
    // TODO: 'A charstring subroutine must end with either an endchar or a return operator.'

}

/// In CID fonts, to get local subroutines we have to:
///   1. Find Font DICT index via FDSelect by GID.
///   2. Get Font DICT data from FDArray using this index.
///   3. Get a Private DICT offset from a Font DICT.
///   4. Get a local subroutine offset from Private DICT.
///   5. Parse a local subroutine at offset.
fn parse_cid_local_subrs(
    data: []const u8,
    glyph_id: lib.GlyphId,
    cid: *const CIDMetadata,
) parser.Error!Index {
    const font_dict_index = try cid.fd_select.font_dict_index(glyph_id);
    const font_dict_data = cid.fd_array.get(font_dict_index) orelse return error.ParseFail;
    const private_dict_range = try parse_font_dict(font_dict_data);
    const private_dict_data = try utils.slice(data, private_dict_range);

    const private_dict = parse_private_dict(private_dict_data);
    const subroutines_offset = private_dict.local_subroutines_offset orelse return error.ParseFail;

    // 'The local subroutines offset is relative to the beginning
    // of the Private DICT data.'
    const start = try std.math.add(usize, private_dict_range[0], subroutines_offset);
    const subrs_data = try utils.slice(data, start);
    var s = parser.Stream.new(subrs_data);
    return try Index.parse(u16, &s);
}

fn parse_font_dict(
    data: []const u8,
) parser.Error!struct { usize, usize } {
    var operands_buffer: [MAX_OPERANDS_LEN]f64 = @splat(0.0);
    var dict_parser = DictionaryParser.new(data, &operands_buffer);
    while (dict_parser.parse_next()) |operator|
        if (operator[0] == top_dict_operator.PRIVATE_DICT_SIZE_AND_OFFSET)
            return try dict_parser.parse_range();

    return error.ParseFail;
}
fn seac_code_to_glyph_id(
    charset: Charset,
    n: f32,
) ?lib.GlyphId {
    const code = utils.f32_to_u8(n) orelse return null;
    const sid = cff.StringId{Encoding.STANDARD_ENCODING[code]};

    switch (charset) {
        // ISO Adobe charset only defines string ids up to 228 (zcaron)
        .iso_adobe => return if (code <= 228) .{sid[0]} else null,
        .expert, .expert_subset => return null,
        else => return charset.sid_to_gid(sid),
    }
}
