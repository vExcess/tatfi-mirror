const cfg = @import("config");
const parser = @import("../parser.zig");

const LookupList = @import("lookup.zig").LookupList;
const FeatureVariations = @import("feature_variations.zig").FeatureVariations;
const Tag = @import("../lib.zig").Tag;

const LazyArray16 = parser.LazyArray16;
const Offset16 = parser.Offset16;

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
        data_type: T, // core::marker::PhantomData<T>,
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
