//! A [Compact Font Format 2 Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cff2) implementation.

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2charstr

const std = @import("std");
const parser = @import("../../parser.zig");
const idx = @import("index.zig");

const Index = idx.Index;
const ItemVariationStore = @import("../../var_store.zig").ItemVariationStore;
const DictionaryParser = @import("dict.zig").DictionaryParser;

// https://docs.microsoft.com/en-us/typography/opentype/spec/cff2#7-top-dict-data
// 'Operators in DICT may be preceded by up to a maximum of 513 operands.'
const MAX_OPERANDS_LEN: usize = 513;

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

        metadata.global_subrs = try idx.parse_index(u32, &s);
        metadata.char_strings = cs: {
            var scs = try parser.Stream.new_at(data, top_dict.char_strings_offset);
            break :cs try idx.parse_index(u32, &scs);
        };

        if (top_dict.variation_store_offset) |offset| {
            var svs = try parser.Stream.new_at(data, offset);
            svs.skip(u16);
            metadata.item_variation_store = try .parse(&s);
        }

        const offset = top_dict.font_dict_index_offset orelse return metadata;

        s.offset = offset;

        const dict_data_idx = try idx.parse_index(u32, &s);
        var iterator = dict_data_idx.iterator();
        while (iterator.next()) |font_dict_data| {
            // private_dict_range
            const pdr_start, const pdr_end = parse_font_dict(font_dict_data) catch continue;

            // 'Private DICT size and offset, from start of the CFF2 table.'
            if (pdr_start > data.len or pdr_end > data.len) return error.ParseFail;
            const private_dict_data = data[pdr_start..pdr_end];

            const subroutines_offset = parse_private_dict(private_dict_data) catch continue;

            // 'The local subroutines offset is relative to the beginning
            // of the Private DICT data.'
            const start = std.math.add(usize, pdr_start, subroutines_offset) catch continue;

            if (start > data.len) return error.ParseFail;
            var s_inner = parser.Stream.new(data[start..]);
            metadata.local_subrs = try idx.parse_index(u32, &s_inner);

            break;
        }

        return metadata;
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

            const len = f64_to_usize(operands[0]) orelse return error.ParseFail;
            const start = f64_to_usize(operands[0]) orelse return error.ParseFail;
            const end = try std.math.add(usize, start, len);

            return .{ start, end };
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
                return f64_to_usize(operands[0]) orelse error.ParseFail;

            return error.ParseFail;
        }
    }

    return error.ParseFail;
}

fn f64_to_usize(f: f64) ?usize {
    const i = std.math.lossyCast(i64, f);
    return std.math.cast(usize, i);
}
