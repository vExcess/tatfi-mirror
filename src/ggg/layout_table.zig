const cfg = @import("config");
const parser = @import("../parser.zig");

const LookupList = @import("lookup.zig").LookupList;
const FeatureVariations = @import("feature_variations.zig").FeatureVariations;
const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;
const Offset32 = parser.Offset32;

/// A [Layout Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#table-organization).
pub const LayoutTable = struct {
    /// A list of all supported scripts.
    scripts: ScriptList,
    /// A list of all supported features.
    features: FeatureList,
    /// A list of all lookups.
    lookups: LookupList,
    /// Used to substitute an alternate set of lookup tables
    /// to use for any given feature under specified conditions.
    variations: if (cfg.variable_fonts) ?FeatureVariations else void,

    pub fn parse(
        data: []const u8,
    ) parser.Error!LayoutTable {
        var s = parser.Stream.new(data);

        if (try s.read(u16) != 1) return error.ParseFail; // major_version
        const minor_version = try s.read(u16);

        const scripts = s: {
            const offset = try s.read(Offset16);
            if (offset[0] > data.len) return error.ParseFail;

            break :s try ScriptList.parse(data[offset[0]..]);
        };
        const features = f: {
            const offset = try s.read(Offset16);
            if (offset[0] > data.len) return error.ParseFail;

            break :f try FeatureList.parse(data[offset[0]..]);
        };
        const lookups = l: {
            const offset = try s.read(Offset16);
            if (offset[0] > data.len) return error.ParseFail;

            break :l try LookupList.parse(data[offset[0]..]);
        };

        const variations = if (cfg.variable_fonts) v: {
            const variations_offset =
                if (minor_version >= 1) try s.read_optional(Offset32) else null;

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
        records: LazyArray16(TagRecord),
        comptime {
            _ = T;
        }

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
    };
}

/// A [Script Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#script-table-and-language-system-record).
pub const Script = struct {
    /// Script tag.
    tag: Tag,
    /// Default language.
    default_language: ?LanguageSystem,
    /// List of supported languages, excluding the default one. Listed alphabetically.
    languages: LanguageSystemList,
};

/// A [Language System Table](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#language-system-table).
pub const LanguageSystem = struct {
    /// Language tag.
    tag: Tag,
    /// Index of a feature required for this language system.
    required_feature: ?FeatureIndex,
    /// Array of indices into the FeatureList, in arbitrary order.
    feature_indices: LazyArray16(FeatureIndex),
};

/// A [Feature](https://docs.microsoft.com/en-us/typography/opentype/spec/chapter2#feature-table).
pub const Feature = struct {
    tag: Tag,
    lookup_indices: LazyArray16(LookupIndex),
};

const TagRecord = struct {
    tag: Tag,
    offset: Offset16,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 6;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);
            return .{
                .tag = try s.read(Tag),
                .offset = try s.read(Offset16),
            };
        }
    };
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
