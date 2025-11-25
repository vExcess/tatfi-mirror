//! A [Compact Font Format Table](
//! https://docs.microsoft.com/en-us/typography/opentype/spec/cff) implementation.

// Useful links:
// http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/font/pdfs/5176.CFF.pdf
// http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/font/pdfs/5177.Type2.pdf
// https://github.com/opentypejs/opentype.js/blob/master/src/tables/cff.js

const std = @import("std");
const parser = @import("../../parser.zig");
const idx = @import("index.zig");

const GlyphId = @import("../../lib.zig").GlyphId;
const Charset = @import("charset.zig").Charset;
const Encoding = @import("encoding.zig").Encoding;
const StringId = @import("../cff.zig").StringId;
const DictionaryParser = @import("dict.zig").DictionaryParser;

const Index = idx.Index;
const LazyArray16 = parser.LazyArray16;

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

    // Copy of Face::units_per_em().
    // Required to do glyph outlining, since coordinates must be scaled up by this before applying the `matrix`.
    units_per_em: ?u16,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        return try Table.parse_inner(data, null);
    }

    /// The same as [`Table::parse`], with the difference that it allows you to
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
        try idx.skip_index(u16, &s);

        const top_dict = try parse_top_dict(&s);

        // Must be set, otherwise there are nothing to parse.
        if (top_dict.char_strings_offset == 0) return error.ParseFail;

        // String INDEX.
        const strings = try idx.parse_index(u16, &s);

        // Parse Global Subroutines INDEX.
        const global_subrs = try idx.parse_index(u16, &s);

        const char_strings = cs: {
            var scs = try parser.Stream.new_at(data, top_dict.char_strings_offset);
            break :cs try idx.parse_index(u16, &scs);
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
                        break :e try Encoding.parse(&se);
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

    /// Returns a glyph ID by a name.
    pub fn glyph_index_by_name(
        self: Table,
        name: []const u8,
    ) ?GlyphId {
        if (self.kind == .cid) return null;

        const sid: StringId = sid: for (STANDARD_NAMES, 0..) |n, pos| {
            if (std.mem.eql(u8, n, name)) break :sid .{@truncate(pos)};
        } else {
            var iter = self.strings.iterator();
            var pos: usize = 0;

            const index = while (iter.next()) |n| : (pos += 1) {
                if (std.mem.eql(u8, n, name)) break pos;
            } else return null;
            break :sid .{@truncate(index + STANDARD_NAMES.len)};
        };

        return self.charset.sid_to_gid(sid);
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
};

const TopDict = struct {
    charset_offset: ?usize = null,
    encoding_offset: ?usize = null,
    char_strings_offset: usize = 0,
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

    const index = try idx.parse_index(u16, s);
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
        break :m try idx.parse_index(u16, &s);
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
        const start, const end = private_dict_range;
        if (start > data.len) return error.ParseFail;
        if (end > data.len) return error.ParseFail;
        break :d parse_private_dict(data[start..end]);
    };

    metadata.default_width = private_dict.default_width orelse 0.0;
    metadata.nominal_width = private_dict.nominal_width orelse 0.0;

    if (private_dict.local_subroutines_offset) |subroutines_offset|
        // 'The local subroutines offset is relative to the beginning
        // of the Private DICT data.'
        if (std.math.add(usize, private_dict_range[0], subroutines_offset)) |start| {
            if (start > data.len) return error.ParseFail;
            var s = parser.Stream.new(data[start..]);
            metadata.local_subrs = try idx.parse_index(u16, &s);
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

pub const STANDARD_NAMES: []const []const u8 = &.{
    ".notdef",            "space",             "exclam",              "quotedbl",
    "numbersign",         "dollar",            "percent",             "ampersand",
    "quoteright",         "parenleft",         "parenright",          "asterisk",
    "plus",               "comma",             "hyphen",              "period",
    "slash",              "zero",              "one",                 "two",
    "three",              "four",              "five",                "six",
    "seven",              "eight",             "nine",                "colon",
    "semicolon",          "less",              "equal",               "greater",
    "question",           "at",                "A",                   "B",
    "C",                  "D",                 "E",                   "F",
    "G",                  "H",                 "I",                   "J",
    "K",                  "L",                 "M",                   "N",
    "O",                  "P",                 "Q",                   "R",
    "S",                  "T",                 "U",                   "V",
    "W",                  "X",                 "Y",                   "Z",
    "bracketleft",        "backslash",         "bracketright",        "asciicircum",
    "underscore",         "quoteleft",         "a",                   "b",
    "c",                  "d",                 "e",                   "f",
    "g",                  "h",                 "i",                   "j",
    "k",                  "l",                 "m",                   "n",
    "o",                  "p",                 "q",                   "r",
    "s",                  "t",                 "u",                   "v",
    "w",                  "x",                 "y",                   "z",
    "braceleft",          "bar",               "braceright",          "asciitilde",
    "exclamdown",         "cent",              "sterling",            "fraction",
    "yen",                "florin",            "section",             "currency",
    "quotesingle",        "quotedblleft",      "guillemotleft",       "guilsinglleft",
    "guilsinglright",     "fi",                "fl",                  "endash",
    "dagger",             "daggerdbl",         "periodcentered",      "paragraph",
    "bullet",             "quotesinglbase",    "quotedblbase",        "quotedblright",
    "guillemotright",     "ellipsis",          "perthousand",         "questiondown",
    "grave",              "acute",             "circumflex",          "tilde",
    "macron",             "breve",             "dotaccent",           "dieresis",
    "ring",               "cedilla",           "hungarumlaut",        "ogonek",
    "caron",              "emdash",            "AE",                  "ordfeminine",
    "Lslash",             "Oslash",            "OE",                  "ordmasculine",
    "ae",                 "dotlessi",          "lslash",              "oslash",
    "oe",                 "germandbls",        "onesuperior",         "logicalnot",
    "mu",                 "trademark",         "Eth",                 "onehalf",
    "plusminus",          "Thorn",             "onequarter",          "divide",
    "brokenbar",          "degree",            "thorn",               "threequarters",
    "twosuperior",        "registered",        "minus",               "eth",
    "multiply",           "threesuperior",     "copyright",           "Aacute",
    "Acircumflex",        "Adieresis",         "Agrave",              "Aring",
    "Atilde",             "Ccedilla",          "Eacute",              "Ecircumflex",
    "Edieresis",          "Egrave",            "Iacute",              "Icircumflex",
    "Idieresis",          "Igrave",            "Ntilde",              "Oacute",
    "Ocircumflex",        "Odieresis",         "Ograve",              "Otilde",
    "Scaron",             "Uacute",            "Ucircumflex",         "Udieresis",
    "Ugrave",             "Yacute",            "Ydieresis",           "Zcaron",
    "aacute",             "acircumflex",       "adieresis",           "agrave",
    "aring",              "atilde",            "ccedilla",            "eacute",
    "ecircumflex",        "edieresis",         "egrave",              "iacute",
    "icircumflex",        "idieresis",         "igrave",              "ntilde",
    "oacute",             "ocircumflex",       "odieresis",           "ograve",
    "otilde",             "scaron",            "uacute",              "ucircumflex",
    "udieresis",          "ugrave",            "yacute",              "ydieresis",
    "zcaron",             "exclamsmall",       "Hungarumlautsmall",   "dollaroldstyle",
    "dollarsuperior",     "ampersandsmall",    "Acutesmall",          "parenleftsuperior",
    "parenrightsuperior", "twodotenleader",    "onedotenleader",      "zerooldstyle",
    "oneoldstyle",        "twooldstyle",       "threeoldstyle",       "fouroldstyle",
    "fiveoldstyle",       "sixoldstyle",       "sevenoldstyle",       "eightoldstyle",
    "nineoldstyle",       "commasuperior",     "threequartersemdash", "periodsuperior",
    "questionsmall",      "asuperior",         "bsuperior",           "centsuperior",
    "dsuperior",          "esuperior",         "isuperior",           "lsuperior",
    "msuperior",          "nsuperior",         "osuperior",           "rsuperior",
    "ssuperior",          "tsuperior",         "ff",                  "ffi",
    "ffl",                "parenleftinferior", "parenrightinferior",  "Circumflexsmall",
    "hyphensuperior",     "Gravesmall",        "Asmall",              "Bsmall",
    "Csmall",             "Dsmall",            "Esmall",              "Fsmall",
    "Gsmall",             "Hsmall",            "Ismall",              "Jsmall",
    "Ksmall",             "Lsmall",            "Msmall",              "Nsmall",
    "Osmall",             "Psmall",            "Qsmall",              "Rsmall",
    "Ssmall",             "Tsmall",            "Usmall",              "Vsmall",
    "Wsmall",             "Xsmall",            "Ysmall",              "Zsmall",
    "colonmonetary",      "onefitted",         "rupiah",              "Tildesmall",
    "exclamdownsmall",    "centoldstyle",      "Lslashsmall",         "Scaronsmall",
    "Zcaronsmall",        "Dieresissmall",     "Brevesmall",          "Caronsmall",
    "Dotaccentsmall",     "Macronsmall",       "figuredash",          "hypheninferior",
    "Ogoneksmall",        "Ringsmall",         "Cedillasmall",        "questiondownsmall",
    "oneeighth",          "threeeighths",      "fiveeighths",         "seveneighths",
    "onethird",           "twothirds",         "zerosuperior",        "foursuperior",
    "fivesuperior",       "sixsuperior",       "sevensuperior",       "eightsuperior",
    "ninesuperior",       "zeroinferior",      "oneinferior",         "twoinferior",
    "threeinferior",      "fourinferior",      "fiveinferior",        "sixinferior",
    "seveninferior",      "eightinferior",     "nineinferior",        "centinferior",
    "dollarinferior",     "periodinferior",    "commainferior",       "Agravesmall",
    "Aacutesmall",        "Acircumflexsmall",  "Atildesmall",         "Adieresissmall",
    "Aringsmall",         "AEsmall",           "Ccedillasmall",       "Egravesmall",
    "Eacutesmall",        "Ecircumflexsmall",  "Edieresissmall",      "Igravesmall",
    "Iacutesmall",        "Icircumflexsmall",  "Idieresissmall",      "Ethsmall",
    "Ntildesmall",        "Ogravesmall",       "Oacutesmall",         "Ocircumflexsmall",
    "Otildesmall",        "Odieresissmall",    "OEsmall",             "Oslashsmall",
    "Ugravesmall",        "Uacutesmall",       "Ucircumflexsmall",    "Udieresissmall",
    "Yacutesmall",        "Thornsmall",        "Ydieresissmall",      "001.000",
    "001.001",            "001.002",           "001.003",             "Black",
    "Bold",               "Book",              "Light",               "Medium",
    "Regular",            "Roman",             "Semibold",
};
