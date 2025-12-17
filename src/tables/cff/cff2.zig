//! A [Compact Font Format 2 Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cff2) implementation.

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2charstr

const std = @import("std");
const lib = @import("../../lib.zig");
const parser = @import("../../parser.zig");
const cff = @import("../cff.zig");
const utils = @import("../../utils.zig");

const Index = @import("index.zig");
const ItemVariationStore = @import("../../var_store.zig");
const DictionaryParser = @import("dict.zig");
const CharStringParser = @import("charstring.zig");

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2#7-top-dict-data
// 'Operators in DICT may be preceded by up to a maximum of 513 operands.'
const MAX_OPERANDS_LEN: usize = 513;

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2charstr#appendix-b-cff2-charstring-implementation-limits
const STACK_LIMIT: u8 = 10;
const MAX_ARGUMENTS_STACK_LEN: usize = 513;

const TWO_BYTE_OPERATOR_MARK: u8 = 12;

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2#table-9-top-dict-operator-entries
const top_dict_operator = struct {
    pub const CHAR_STRINGS_OFFSET: u16 = 17;
    pub const VARIATION_STORE_OFFSET: u16 = 24;
    pub const FONT_DICT_INDEX_OFFSET: u16 = 1236;
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2#table-10-font-dict-operator-entries
const font_dict_operator = struct {
    pub const PRIVATE_DICT_SIZE_AND_OFFSET: u16 = 18;
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2#table-16-private-dict-operators
const private_dict_operator = struct {
    pub const LOCAL_SUBROUTINES_OFFSET: u16 = 19;
};

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2charstr#4-charstring-operators
const ms_operator = struct {
    pub const HORIZONTAL_STEM: u8 = 1;
    pub const VERTICAL_STEM: u8 = 3;
    pub const VERTICAL_MOVE_TO: u8 = 4;
    pub const LINE_TO: u8 = 5;
    pub const HORIZONTAL_LINE_TO: u8 = 6;
    pub const VERTICAL_LINE_TO: u8 = 7;
    pub const CURVE_TO: u8 = 8;
    pub const CALL_LOCAL_SUBROUTINE: u8 = 10;
    pub const VS_INDEX: u8 = 15;
    pub const BLEND: u8 = 16;
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

/// A [Compact Font Format 2 Table](
/// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2).
pub const Table = struct {
    global_subrs: Index = .default,
    local_subrs: Index = .default,
    char_strings: Index = .default,
    item_variation_store: ItemVariationStore = .{},

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);

        // Parse Header.
        if (try s.read(u8) != 2) return error.ParseFail; // major
        s.skip(u8); // minor
        const header_size = try s.read(u8);
        const top_dict_length = try s.read(u16);

        // Jump to Top DICT. It's not necessarily right after the header.
        s.advance(header_size -| 5);

        const top_dict_data = try s.read_bytes(top_dict_length);
        const top_dict: TopDictData = try .parse(top_dict_data);

        var metadata: Table = .{};

        metadata.global_subrs = try Index.parse(u32, &s);
        metadata.char_strings = cs: {
            var scs = try parser.Stream.new_at(data, top_dict.char_strings_offset);
            break :cs try Index.parse(u32, &scs);
        };

        if (top_dict.variation_store_offset) |offset| {
            var svs = try parser.Stream.new_at(data, offset);
            svs.skip(u16);
            metadata.item_variation_store = try .parse(&s);
        }

        const offset = top_dict.font_dict_index_offset orelse return metadata;

        s.offset = offset;

        const dict_data_idx = try Index.parse(u32, &s);
        var iterator = dict_data_idx.iterator();
        while (iterator.next()) |font_dict_data| {
            // private_dict_range
            const pdr_start, const pdr_len = parse_font_dict(font_dict_data) catch continue;

            // 'Private DICT size and offset, from start of the CFF2 table.'
            const private_dict_data = try utils.slice(data, .{ pdr_start, pdr_len });

            const subroutines_offset = parse_private_dict(private_dict_data) catch continue;

            // 'The local subroutines offset is relative to the beginning
            // of the Private DICT data.'
            const start = std.math.add(usize, pdr_start, subroutines_offset) catch continue;

            var s_inner = parser.Stream.new(try utils.slice(data, start));
            metadata.local_subrs = try Index.parse(u32, &s_inner);

            break;
        }

        return metadata;
    }

    pub fn outline(
        self: *const Table,
        coordinates: []const lib.NormalizedCoordinate,
        glyph_id: lib.GlyphId,
        builder: lib.OutlineBuilder,
    ) cff.Error!lib.Rect {
        const data = self.char_strings.get(glyph_id[0]) orelse return error.NoGlyph;
        return try parse_char_string(data, self, coordinates, builder);
    }
};

const TopDictData = struct {
    char_strings_offset: usize = 0,
    font_dict_index_offset: ?usize = null,
    variation_store_offset: ?usize = null,

    fn parse(
        data: []const u8,
    ) parser.Error!TopDictData {
        var dict_data: TopDictData = .{};

        var operands_buffer: [MAX_OPERANDS_LEN]f64 = @splat(0.0);
        var dict_parser: DictionaryParser = .new(data, &operands_buffer);

        while (dict_parser.parse_next()) |operator| switch (operator[0]) {
            top_dict_operator.CHAR_STRINGS_OFFSET => dict_data
                .char_strings_offset = try dict_parser.parse_offset(),

            top_dict_operator.FONT_DICT_INDEX_OFFSET => dict_data
                .font_dict_index_offset = dict_parser.parse_offset() catch null,

            top_dict_operator.VARIATION_STORE_OFFSET => dict_data
                .variation_store_offset = dict_parser.parse_offset() catch null,

            else => {},
        };

        // Must be set, otherwise there are nothing to parse.
        if (dict_data.char_strings_offset == 0) return error.ParseFail;

        return dict_data;
    }
};

fn parse_font_dict(
    data: []const u8,
) parser.Error!struct { usize, usize } {
    var operands_buffer: [MAX_OPERANDS_LEN]f64 = @splat(0.0);
    var dict_parser: DictionaryParser = .new(data, &operands_buffer);

    while (dict_parser.parse_next()) |operator| {
        if (operator[0] == font_dict_operator.PRIVATE_DICT_SIZE_AND_OFFSET) {
            try dict_parser.parse_operands();
            const operands = dict_parser.operands_slice();

            if (operands.len != 2) return error.ParseFail;

            const len = utils.f64_to_usize(operands[0]) orelse return error.ParseFail;
            const start = utils.f64_to_usize(operands[0]) orelse return error.ParseFail;

            return .{ start, len };
        }
    }
    return error.ParseFail;
}

fn parse_private_dict(
    data: []const u8,
) parser.Error!usize {
    var operands_buffer: [MAX_OPERANDS_LEN]f64 = @splat(0.0);
    var dict_parser: DictionaryParser = .new(data, &operands_buffer);

    while (dict_parser.parse_next()) |operator| {
        if (operator[0] == private_dict_operator.LOCAL_SUBROUTINES_OFFSET) {
            try dict_parser.parse_operands();
            const operands = dict_parser.operands_slice();

            if (operands.len == 1)
                return utils.f64_to_usize(operands[0]) orelse error.ParseFail;

            return error.ParseFail;
        }
    }

    return error.ParseFail;
}

/// CFF2 allows up to 65535 scalars, but an average font will have 3-5.
/// So 64 is more than enough.
const SCALARS_MAX: u8 = 64;

const CharStringParserContext = struct {
    metadata: *const Table,
    coordinates: []const lib.NormalizedCoordinate,
    scalars: std.ArrayList(f32),
    had_vsindex: bool,
    had_blend: bool,
    stems_len: u32,

    fn update_scalars(
        self: *CharStringParserContext,
        index: u16,
    ) cff.Error!void {
        self.scalars.clearRetainingCapacity();

        const indices = self
            .metadata
            .item_variation_store
            .region_indices(index) orelse return error.InvalidItemVariationDataIndex;

        var iter = indices.iterator();
        while (iter.next()) |idx| {
            const scalar = self
                .metadata
                .item_variation_store
                .regions
                .evaluate_region(idx, self.coordinates);
            self.scalars.appendBounded(scalar) catch return error.BlendRegionsLimitReached;
        }
    }
};

fn parse_char_string(
    data: []const u8,
    metadata: *const Table,
    coordinates: []const lib.NormalizedCoordinate,
    builder: lib.OutlineBuilder,
) cff.Error!lib.Rect {
    var scalar_buffer: [SCALARS_MAX]f32 = @splat(0.0); // 256B

    var ctx = CharStringParserContext{
        .metadata = metadata,
        .coordinates = coordinates,
        .scalars = .initBuffer(&scalar_buffer),
        .had_vsindex = false,
        .had_blend = false,
        .stems_len = 0,
    };

    // Load scalars at default index.
    try ctx.update_scalars(0);

    var inner_builder: cff.Builder = .{ .builder = builder, .bbox = .{}, .transform_tuple = null };

    var stack_buffer: [MAX_ARGUMENTS_STACK_LEN]f32 = @splat(0.0);

    var cs_parser: CharStringParser = .{
        .stack = .initBuffer(&stack_buffer),
        .builder = &inner_builder,
        .x = 0.0,
        .y = 0.0,
        .has_move_to = false,
        .is_first_move_to = true,
        .width_only = false,
    };
    try parse_char_string_recursive(&ctx, data, 0, &cs_parser);

    const bbox = cs_parser.builder.bbox;

    // Check that bbox was changed.
    if (bbox.is_default()) return error.ZeroBBox;

    return bbox.to_rect() orelse error.BboxOverflow;
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
            0, 2, 9, 11, 13, 14, 17 => return error.InvalidOperator,
            ms_operator.HORIZONTAL_STEM,
            ms_operator.VERTICAL_STEM,
            ms_operator.HORIZONTAL_STEM_HINT_MASK,
            ms_operator.VERTICAL_STEM_HINT_MASK,
            => {
                // y dy {dya dyb}* hstem
                // x dx {dxa dxb}* vstem
                // y dy {dya dyb}* hstemhm
                // x dx {dxa dxb}* vstemhm

                ctx.stems_len += @as(u32, @truncate(p.stack.items.len)) >> 1;

                // We are ignoring the hint operators.
                p.stack.clearRetainingCapacity();
            },
            ms_operator.VERTICAL_MOVE_TO => try p.parse_vertical_move_to(0),
            ms_operator.LINE_TO => try p.parse_line_to(),
            ms_operator.HORIZONTAL_LINE_TO => try p.parse_horizontal_line_to(),
            ms_operator.VERTICAL_LINE_TO => try p.parse_vertical_line_to(),
            ms_operator.CURVE_TO => try p.parse_curve_to(),
            ms_operator.CALL_LOCAL_SUBROUTINE => {
                if (p.stack.items.len == 0) return error.InvalidArgumentsStackLength;
                if (depth == STACK_LIMIT) return error.NestingLimitReached;

                const subroutine_bias =
                    cff.calc_subroutine_bias(ctx.metadata.local_subrs.len());
                const index = try cff.conv_subroutine_index(
                    p.stack.pop() orelse unreachable,
                    subroutine_bias,
                );
                const local_char_string = ctx
                    .metadata
                    .local_subrs
                    .get(index) orelse return error.InvalidSubroutineIndex;
                try parse_char_string_recursive(ctx, local_char_string, depth + 1, p);
            },
            TWO_BYTE_OPERATOR_MARK => {
                // flex
                const op2 = s.read(u8) catch return error.ReadOutOfBounds;
                switch (op2) {
                    ms_operator.HFLEX => try p.parse_hflex(),
                    ms_operator.FLEX => try p.parse_flex(),
                    ms_operator.HFLEX1 => try p.parse_hflex1(),
                    ms_operator.FLEX1 => try p.parse_flex1(),
                    else => return error.UnsupportedOperator,
                }
            },
            ms_operator.VS_INDEX => {
                // |- ivs vsindex (15) |-

                // `vsindex` must precede the first `blend` operator, and may occur only once.
                if (ctx.had_blend and ctx.had_vsindex) return error.InvalidOperator;
                if (p.stack.items.len != 1) return error.InvalidArgumentsStackLength;

                const index = utils.f32_to_u16(p.stack.pop() orelse unreachable) orelse
                    return error.InvalidItemVariationDataIndex;
                try ctx.update_scalars(index);

                ctx.had_vsindex = true;

                p.stack.clearRetainingCapacity();
            },
            ms_operator.BLEND => {
                // num(0)..num(n-1), delta(0,0)..delta(k-1,0),
                // delta(0,1)..delta(k-1,1) .. delta(0,n-1)..delta(k-1,n-1)
                // n blend (16) val(0)..val(n-1)

                ctx.had_blend = true;

                const n = utils.f32_to_u16((p.stack.pop() orelse unreachable)) orelse
                    return error.InvalidNumberOfBlendOperands;
                const k = ctx.scalars.items.len;

                const len = @as(usize, n) * (@as(usize, k) + 1);
                if (p.stack.items.len < len) return error.InvalidArgumentsStackLength;

                const start = p.stack.items.len - len;
                for (0..n) |i_true| {
                    const i = n - 1 - i_true;
                    for (0..k) |j| {
                        const delta = p.stack.pop() orelse unreachable;
                        p.stack.items[start + i] += delta * ctx.scalars.items[k - j - 1];
                    }
                }
            },
            ms_operator.HINT_MASK, ms_operator.COUNTER_MASK => {
                ctx.stems_len += @as(u32, @truncate(p.stack.items.len)) >> 1;
                s.advance((ctx.stems_len + 7) >> 3);

                // We are ignoring the hint operators.
                p.stack.clearRetainingCapacity();
            },
            ms_operator.MOVE_TO => try p.parse_move_to(0),
            ms_operator.HORIZONTAL_MOVE_TO => try p.parse_horizontal_move_to(0),
            ms_operator.CURVE_LINE => try p.parse_curve_line(),
            ms_operator.LINE_CURVE => try p.parse_line_curve(),
            ms_operator.VV_CURVE_TO => try p.parse_vv_curve_to(),
            ms_operator.HH_CURVE_TO => try p.parse_hh_curve_to(),
            ms_operator.SHORT_INT => {
                const n = s.read(i16) catch return error.ReadOutOfBounds;
                p.stack.appendBounded(@floatFromInt(n)) catch
                    return error.ArgumentsStackLimitReached;
            },
            ms_operator.CALL_GLOBAL_SUBROUTINE => {
                if (p.stack.items.len == 0) return error.InvalidArgumentsStackLength;
                if (depth == STACK_LIMIT) return error.NestingLimitReached;

                const subroutine_bias =
                    cff.calc_subroutine_bias(ctx.metadata.global_subrs.len());
                const index = try cff.conv_subroutine_index(
                    (p.stack.pop() orelse unreachable),
                    subroutine_bias,
                );
                const global_char_string = ctx
                    .metadata
                    .global_subrs
                    .get(index) orelse return error.InvalidSubroutineIndex;
                try parse_char_string_recursive(ctx, global_char_string, depth + 1, p);
            },
            ms_operator.VH_CURVE_TO => try p.parse_vh_curve_to(),
            ms_operator.HV_CURVE_TO => try p.parse_hv_curve_to(),
            32...246 => try p.parse_int1(op),
            247...250 => try p.parse_int2(op, &s),
            251...254 => try p.parse_int3(op, &s),
            ms_operator.FIXED_16_16 => try p.parse_fixed(&s),
        }
        //
    }
}
