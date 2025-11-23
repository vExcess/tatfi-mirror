//! A [OS/2 and Windows Metrics Table](https://docs.microsoft.com/en-us/typography/opentype/spec/os2)
//! implementation.

const parser = @import("../parser.zig");

const WEIGHT_CLASS_OFFSET: usize = 4;
const WIDTH_CLASS_OFFSET: usize = 6;
const TYPE_OFFSET: usize = 8;
const Y_SUBSCRIPT_X_SIZE_OFFSET: usize = 10;
const Y_SUPERSCRIPT_X_SIZE_OFFSET: usize = 18;
const Y_STRIKEOUT_SIZE_OFFSET: usize = 26;
const Y_STRIKEOUT_POSITION_OFFSET: usize = 28;
const UNICODE_RANGES_OFFSET: usize = 42;
const SELECTION_OFFSET: usize = 62;
const TYPO_ASCENDER_OFFSET: usize = 68;
const TYPO_DESCENDER_OFFSET: usize = 70;
const TYPO_LINE_GAP_OFFSET: usize = 72;
const WIN_ASCENT: usize = 74;
const WIN_DESCENT: usize = 76;
const X_HEIGHT_OFFSET: usize = 86;
const CAP_HEIGHT_OFFSET: usize = 88;

/// A [OS/2 and Windows Metrics Table](https://docs.microsoft.com/en-us/typography/opentype/spec/os2).
pub const Table = struct {
    /// Table version.
    version: u8,
    data: []const u8,

    /// Parses a table from raw data.
    pub fn parse(
        data: []const u8,
    ) parser.Error!Table {
        var s = parser.Stream.new(data);
        const version = try s.read(u16);

        const table_len: usize = switch (version) {
            0 => 78,
            1 => 86,
            2 => 96,
            3 => 96,
            4 => 96,
            5 => 100,
            else => return error.ParseFail,
        };

        // Do not check the exact length, because some fonts include
        // padding in table's length in table records, which is incorrect.
        if (data.len < table_len) return error.ParseFail;

        return .{
            .version = @truncate(version),
            .data = data,
        };
    }

    fn fs_selection(
        self: Table,
    ) packed struct(u16) {
        italic: bool = false,
        _0: u4 = 0,
        bold: bool = false,
        regular: bool = false,
        use_typo_metrics: bool = false,
        _1: u1 = 0,
        oblique: bool = false,
        _2: u6 = 0,
    } {
        var s = parser.Stream.new_at(self.data, SELECTION_OFFSET) catch return .{};
        const f = s.read(u16) catch return .{};

        return @bitCast(f);
    }

    /// Returns style.
    pub fn style(
        self: Table,
    ) Style {
        const flags = self.fs_selection();
        if (flags.italic)
            return .italic
        else if (self.version >= 4 and flags.oblique)
            return .oblique
        else
            return .normal;
    }

    /// Checks if face is bold.
    ///
    /// Do not confuse with [`Weight::Bold`].
    pub fn is_bold(
        self: Table,
    ) bool {
        return self.fs_selection().bold;
    }

    /// Returns weight class.
    pub fn weight(
        self: Table,
    ) Weight {
        const f: u16 = f: {
            var s = parser.Stream.new_at(self.data, WEIGHT_CLASS_OFFSET) catch break :f 0;
            break :f s.read(u16) catch 0;
        };
        return Weight.from(f);
    }

    /// Returns face width.
    pub fn width(
        self: Table,
    ) Width {
        var s = parser.Stream.new_at(self.data, WIDTH_CLASS_OFFSET) catch return .normal;
        const n: u16 = s.read(u16) catch 0;
        return switch (n) {
            1 => .ultra_condensed,
            2 => .extra_condensed,
            3 => .condensed,
            4 => .semi_condensed,
            5 => .normal,
            6 => .semi_expanded,
            7 => .expanded,
            8 => .extra_expanded,
            9 => .ultra_expanded,
            else => .normal,
        };
    }

    /// Checks if typographic metrics should be used.
    pub fn use_typographic_metrics(
        self: Table,
    ) bool {
        return self.version >= 4 and self.fs_selection().use_typo_metrics;
    }

    /// Returns typographic ascender.
    pub fn typographic_ascender(
        self: Table,
    ) i16 {
        var s = parser.Stream.new_at(self.data, TYPO_ASCENDER_OFFSET) catch return 0;
        return s.read(i16) catch 0;
    }

    /// Returns Windows ascender.
    pub fn windows_ascender(
        self: Table,
    ) i16 {
        var s = parser.Stream.new_at(self.data, WIN_ASCENT) catch return 0;
        return s.read(i16) catch 0;
    }

    /// Returns typographic descender.
    pub fn typographic_descender(
        self: Table,
    ) i16 {
        var s = parser.Stream.new_at(self.data, TYPO_DESCENDER_OFFSET) catch return 0;
        return s.read(i16) catch 0;
    }

    /// Returns Windows descender
    pub fn windows_descender(
        self: Table,
    ) i16 {
        var s = parser.Stream.new_at(self.data, WIN_DESCENT) catch return 0;
        return -(s.read(i16) catch 0);
    }

    /// Returns typographic line gap.
    pub fn typographic_line_gap(
        self: Table,
    ) i16 {
        var s = parser.Stream.new_at(self.data, TYPO_LINE_GAP_OFFSET) catch return 0;
        return s.read(i16) catch 0;
    }

    /// Returns x height.
    ///
    /// Returns `null` version is < 2.
    pub fn x_height(
        self: Table,
    ) ?i16 {
        if (self.version < 2) {
            return null;
        } else {
            var s = parser.Stream.new_at(self.data, X_HEIGHT_OFFSET) catch return null;
            return s.read(i16) catch null;
        }
    }

    /// Returns capital height.
    ///
    /// Returns `null` version is < 2.
    pub fn capital_height(
        self: Table,
    ) ?i16 {
        if (self.version < 2) {
            return null;
        } else {
            var s = parser.Stream.new_at(self.data, CAP_HEIGHT_OFFSET) catch return null;
            return s.read(i16) catch null;
        }
    }
};

/// A face style.
pub const Style = enum {
    /// A face that is neither italic not obliqued.
    normal,
    /// A form that is generally cursive in nature.
    italic,
    /// A typically-sloped version of the regular face.
    oblique,
};

/// A face [weight](https://docs.microsoft.com/en-us/typography/opentype/spec/os2#usweightclass).
pub const Weight = union(enum) {
    thin,
    extra_light,
    light,
    normal,
    medium,
    semi_bold,
    bold,
    extra_bold,
    black,
    other: u16,

    fn from(
        value: u16,
    ) Weight {
        return switch (value) {
            100 => .thin,
            200 => .extra_light,
            300 => .light,
            400 => .normal,
            500 => .medium,
            600 => .semi_bold,
            700 => .bold,
            800 => .extra_bold,
            900 => .black,
            else => .{ .other = value },
        };
    }

    /// Returns a numeric representation of a weight.
    pub fn to_number(
        self: Weight,
    ) u16 {
        return switch (self) {
            .thin => 100,
            .extra_light => 200,
            .light => 300,
            .normal => 400,
            .medium => 500,
            .semi_bold => 600,
            .bold => 700,
            .extra_bold => 800,
            .black => 900,
            .other => |n| n,
        };
    }
};

/// A face [width](https://docs.microsoft.com/en-us/typography/opentype/spec/os2#uswidthclass).
pub const Width = enum {
    ultra_condensed,
    extra_condensed,
    condensed,
    semi_condensed,
    normal,
    semi_expanded,
    expanded,
    extra_expanded,
    ultra_expanded,
};
