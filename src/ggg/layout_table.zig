const std = @import("std");
const cfg = @import("config");
const lib = @import("../lib.zig");
const parser = @import("../parser.zig");

const LookupKind = @import("lookup.zig").LookupSubtable;
const LookupList = @import("lookup.zig").LookupList;
const FeatureVariations = @import("feature_variations.zig").FeatureVariations;

/// A [Layout Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#table-organization).
pub fn LayoutTable(subtable: LookupKind) type {
    return struct {
        /// A list of all supported scripts.
        scripts: ScriptList,
        /// A list of all supported features.
        features: FeatureList,
        /// A list of all lookups.
        lookups: LookupList(subtable),
        /// Used to substitute an alternate set of lookup tables
        /// to use for any given feature under specified conditions.
        variations: if (cfg.variable_fonts) ?FeatureVariations else void,

        const Self = @This();

        pub fn parse(
            data: []const u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);

            if (try s.read(u16) != 1) return error.ParseFail; // major_version
            const minor_version = try s.read(u16);

            const scripts = s: {
                const offset = try s.read(parser.Offset16);
                if (offset[0] > data.len) return error.ParseFail;

                break :s try ScriptList.parse(data[offset[0]..]);
            };
            const features = f: {
                const offset = try s.read(parser.Offset16);
                if (offset[0] > data.len) return error.ParseFail;

                break :f try FeatureList.parse(data[offset[0]..]);
            };
            const lookups = l: {
                const offset = try s.read(parser.Offset16);
                if (offset[0] > data.len) return error.ParseFail;

                break :l try LookupList(subtable).parse(data[offset[0]..]);
            };

            const variations = if (cfg.variable_fonts) v: {
                const variations_offset =
                    if (minor_version >= 1) try s.read_optional(parser.Offset32) else null;

                const offset = variations_offset orelse break :v null;
                if (offset[0] > data.len) break :v null;

                break :v FeatureVariations.parse(data[offset[0]..]) catch null;
            } else {};

            return .{
                .scripts = scripts,
                .features = features,
                .lookups = lookups,
                .variations = variations,
            };
        }
    };
}

/// A list of [`Script`] records.
pub const ScriptList = RecordList(Script);
/// A list of [`LanguageSystem`] records.
pub const LanguageSystemList = RecordList(LanguageSystem);
/// A list of [`Feature`] records.
pub const FeatureList = RecordList(Feature);

/// A data storage used by [`ScriptList`], [`LanguageSystemList`] and [`FeatureList`] data types.
// [ARS] currently a stub
pub fn RecordList(T: type) type {
    // [ARS] T should implement the RecordListItem trait, somehow
    return struct {
        data: []const u8,
        records: parser.LazyArray16(TagRecord),

        const Self = @This();

        fn parse(
            data: []const u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            const count = try s.read(u16);
            const records = try s.read_array(TagRecord, count);
            return .{
                .data = data,
                .records = records,
            };
        }

        /// Returns RecordList value by index.
        pub fn get(
            self: Self,
            idx: u16,
        ) ?T {
            const record = self.records.get(idx) orelse return null;
            if (record.offset[0] > self.data.len) return null;
            const data = self.data[record.offset[0]..];

            return T.parse(record.tag, data) catch null;
        }

        /// Returns RecordList value by [`Tag`].
        pub fn find(
            self: Self,
            tag: lib.Tag,
        ) ?T {
            _, const record = self.records.binary_search_by(
                tag,
                TagRecord.compare,
            ) orelse return null;
            if (record.offset[0] > self.data.len) return null;
            const data = self.data[record.offset[0]..];
            return T.parse(record.tag, data) catch null;
        }

        /// Returns RecordList value index by [`Tag`].
        pub fn index(
            self: Self,
            tag: lib.Tag,
        ) ?u16 {
            const i, _ = self.records.binary_search_by(
                tag,
                TagRecord.compare,
            ) orelse return null;
            return i;
        }

        pub fn iterator(
            self: *const Self,
        ) Iterator {
            return .{ .list = self };
        }

        pub const Iterator = struct {
            list: *const Self,
            idx: u16 = 0,

            pub fn next(
                self: *Iterator,
            ) ?T {
                if (self.idx < self.list.records.len()) {
                    defer self.idx += 1;
                    return self.list.get(self.idx);
                } else return null;
            }
        };
    };
}

/// A [Script Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#script-table-and-language-system-record).
pub const Script = struct {
    /// Script tag.
    tag: lib.Tag,
    /// Default language.
    default_language: ?LanguageSystem,
    /// List of supported languages, excluding the default one. Listed alphabetically.
    languages: LanguageSystemList,

    fn parse(
        tag: lib.Tag,
        data: []const u8,
    ) parser.Error!Script {
        var s = parser.Stream.new(data);
        var default_language: ?LanguageSystem = null;
        if (try s.read_optional(parser.Offset16)) |offset| {
            if (offset[0] > data.len) return error.ParseFail;
            const inner = lib.Tag.from_bytes("dflt");
            default_language = try .parse(.{ .inner = inner }, data[offset[0]..]);
        }

        var languages: LanguageSystemList = try .parse(try s.tail());
        // Offsets are relative to this table.
        languages.data = data;

        return .{
            .tag = tag,
            .default_language = default_language,
            .languages = languages,
        };
    }
};

/// A [Language System Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#language-system-table).
pub const LanguageSystem = struct {
    /// Language tag.
    tag: lib.Tag,
    /// Index of a feature required for this language system.
    required_feature: ?FeatureIndex,
    /// Array of indices into the FeatureList, in arbitrary order.
    feature_indices: parser.LazyArray16(FeatureIndex),

    fn parse(
        tag: lib.Tag,
        data: []const u8,
    ) parser.Error!LanguageSystem {
        var s = parser.Stream.new(data);
        s.skip(parser.Offset16); // lookup_order, Unsupported.

        const v = try s.read(FeatureIndex);
        const required_feature = switch (v) {
            0xFFFF => null,
            else => v,
        };

        const count = try s.read(u16);
        const feature_indices = try s.read_array(FeatureIndex, count);
        return .{
            .tag = tag,
            .required_feature = required_feature,
            .feature_indices = feature_indices,
        };
    }
};

/// A [Feature](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#feature-table).
pub const Feature = struct {
    tag: lib.Tag,
    lookup_indices: parser.LazyArray16(LookupIndex),

    fn parse(
        tag: lib.Tag,
        data: []const u8,
    ) parser.Error!Feature {
        var s = parser.Stream.new(data);
        s.skip(parser.Offset16); // params_offset, Unsupported.
        const count = try s.read(u16);
        const lookup_indices = try s.read_array(LookupIndex, count);
        return .{
            .tag = tag,
            .lookup_indices = lookup_indices,
        };
    }
};

const TagRecord = struct {
    tag: lib.Tag,
    offset: parser.Offset16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 6;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .tag = try s.read(lib.Tag),
                .offset = try s.read(parser.Offset16),
            };
        }
    };

    fn compare(
        record: TagRecord,
        rhs: lib.Tag,
    ) std.math.Order {
        return std.math.order(record.tag.inner, rhs.inner);
    }
};

/// An index in [`ScriptList`].
pub const ScriptIndex = u16;
/// An index in [`LanguageSystemList`].
pub const LanguageIndex = u16;
/// An index in [`FeatureList`].
pub const FeatureIndex = u16;
/// An index in [`LookupList`].
pub const LookupIndex = u16;
/// An index in [`FeatureVariations`].
pub const VariationIndex = u32;
