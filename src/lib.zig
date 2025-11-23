/// A high-level, safe, zero-allocation font parser for:
/// * [TrueType](https://docs.microsoft.com/en-us/typography/truetype/),
/// * [OpenType](https://docs.microsoft.com/en-us/typography/opentype/spec/), and
/// * [AAT](https://developer.apple.com/fonts/TrueType-Reference-Manual/RM06/Chap6AATIntro.html).
///
/// Font parsing starts with a [`Face`].
const std = @import("std");
const cfg = @import("config");
const parser = @import("parser.zig");
const tables = @import("tables.zig");
const opentype_layout = @import("ggg.zig");

const LazyArray16 = parser.LazyArray16;

/// A type-safe wrapper for glyph ID.
pub const GlyphId = struct { u16 };

/// A font face.
///
/// Provides a high-level API for working with TrueType fonts.
/// If you're not familiar with how TrueType works internally, you should use this type.
/// If you do know and want a bit more low-level access - checkout [`FaceTables`].
///
/// Note that `Face` doesn't own the font data and doesn't allocate anything in heap.
/// Therefore you cannot "store" it. The idea is that you should parse the `Face`
/// when needed, get required data and forget about it.
/// That's why the initial parsing is highly optimized and should not become a bottleneck.
///
/// Noe that this struct is almost 2KB big.
pub const Face = struct {
    raw_face: RawFace,
    tables: FaceTables, // Parsed tables.
    coordinates: if (cfg.variable_fonts) VarCoords else void,

    const Self = @This();

    /// Creates a new [`Face`] from a raw data.
    ///
    /// `index` indicates the specific font face in a font collection.
    /// Use [`fonts_in_collection`] to get the total number of font faces.
    /// Set to 0 if unsure.
    ///
    /// This method will do some parsing and sanitization,
    /// but in general can be considered free. No significant performance overhead.
    ///
    /// Required tables: `head`, `hhea` and `maxp`.
    ///
    /// If an optional table has invalid data it will be skipped.
    pub fn parse(
        data: []const u8,
        index: u32,
    ) FaceParsingError!Self {
        const raw_face = try RawFace.parse(data, index);
        const raw_tables: RawFaceTables = Self.collect_tables(raw_face);

        var face: Self = .{
            .raw_face = raw_face,
            .coordinates = if (cfg.variable_fonts) VarCoords{},
            .tables = try Self.parse_tables(raw_tables),
        };

        if (cfg.variable_fonts) if (face.tables.variable_fonts.fvar) |fvar| {
            face.coordinates.len = @min(fvar.axes.len(), MAX_VAR_COORDS);
        };

        return face;
    }

    fn collect_tables(
        raw_face: RawFace,
    ) RawFaceTables {
        var ret_tables: RawFaceTables = .{};

        var iterator = raw_face.table_records.iterator();
        while (iterator.next()) |record| {
            const start: usize = record.offset;
            if (start > raw_face.data.len) continue;

            const end = std.math.add(usize, start, record.length) catch continue;
            if (end > raw_face.data.len) continue;

            const table_data = raw_face.data[start..end];

            switch (record.tag.inner) {
                Tag.from_bytes("bdat") => ret_tables.bdat = table_data,
                Tag.from_bytes("bloc") => ret_tables.bloc = table_data,
                Tag.from_bytes("CBDT") => ret_tables.cbdt = table_data,
                Tag.from_bytes("CBLC") => ret_tables.cblc = table_data,
                Tag.from_bytes("CFF ") => ret_tables.cff = table_data,
                Tag.from_bytes("CFF2") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.cff2 = table_data;
                },
                Tag.from_bytes("COLR") => ret_tables.colr = table_data,
                Tag.from_bytes("CPAL") => ret_tables.cpal = table_data,
                Tag.from_bytes("EBDT") => ret_tables.ebdt = table_data,
                Tag.from_bytes("EBLC") => ret_tables.eblc = table_data,
                Tag.from_bytes("GDEF") => if (cfg.opentype_layout) {
                    ret_tables.opentype_layout.gdef = table_data;
                },
                Tag.from_bytes("GPOS") => if (cfg.opentype_layout) {
                    ret_tables.opentype_layout.gpos = table_data;
                },
                Tag.from_bytes("GSUB") => if (cfg.opentype_layout) {
                    ret_tables.opentype_layout.gsub = table_data;
                },
                Tag.from_bytes("MATH") => if (cfg.opentype_layout) {
                    ret_tables.opentype_layout.math = table_data;
                },
                Tag.from_bytes("HVAR") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.hvar = table_data;
                },
                Tag.from_bytes("MVAR") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.mvar = table_data;
                },
                Tag.from_bytes("OS/2") => ret_tables.os2 = table_data,
                Tag.from_bytes("SVG ") => ret_tables.svg = table_data,
                Tag.from_bytes("VORG") => ret_tables.vorg = table_data,
                Tag.from_bytes("VVAR") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.vvar = table_data;
                },
                Tag.from_bytes("ankr") => if (cfg.apple_layout) {
                    ret_tables.apple_layout.ankr = table_data;
                },
                Tag.from_bytes("avar") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.avar = table_data;
                },
                Tag.from_bytes("cmap") => ret_tables.cmap = table_data,
                Tag.from_bytes("feat") => if (cfg.apple_layout) {
                    ret_tables.apple_layout.feat = table_data;
                },
                Tag.from_bytes("fvar") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.fvar = table_data;
                },
                Tag.from_bytes("glyf") => ret_tables.glyf = table_data,
                Tag.from_bytes("gvar") => if (cfg.variable_fonts) {
                    ret_tables.variable_fonts.gvar = table_data;
                },
                Tag.from_bytes("head") => ret_tables.head = table_data,
                Tag.from_bytes("hhea") => ret_tables.hhea = table_data,
                Tag.from_bytes("hmtx") => ret_tables.hmtx = table_data,
                Tag.from_bytes("kern") => ret_tables.kern = table_data,
                Tag.from_bytes("kerx") => if (cfg.apple_layout) {
                    ret_tables.apple_layout.kerx = table_data;
                },
                Tag.from_bytes("loca") => ret_tables.loca = table_data,
                Tag.from_bytes("maxp") => ret_tables.maxp = table_data,
                Tag.from_bytes("morx") => if (cfg.apple_layout) {
                    ret_tables.apple_layout.morx = table_data;
                },
                Tag.from_bytes("name") => ret_tables.name = table_data,
                Tag.from_bytes("post") => ret_tables.post = table_data,
                Tag.from_bytes("sbix") => ret_tables.sbix = table_data,
                Tag.from_bytes("STAT") => ret_tables.stat = table_data,
                Tag.from_bytes("trak") => if (cfg.apple_layout) {
                    ret_tables.apple_layout.trak = table_data;
                },
                Tag.from_bytes("vhea") => ret_tables.vhea = table_data,
                Tag.from_bytes("vmtx") => ret_tables.vmtx = table_data,
                else => {},
            }
        }

        return ret_tables;
    }

    fn parse_tables(
        raw_tables: RawFaceTables,
    ) FaceParsingError!FaceTables {
        const head = tables.head.Table.parse(raw_tables.head) catch
            return error.NoHeadTable;
        const hhea = tables.hhea.Table.parse(raw_tables.hhea) catch
            return error.NoHheaTable;
        const maxp = tables.maxp.Table.parse(raw_tables.maxp) catch
            return error.NoMaxpTable;

        const hmtx = t: {
            const data = raw_tables.hmtx orelse break :t null;
            break :t tables.hmtx.Table.parse(
                hhea.number_of_metrics,
                maxp.number_of_glyphs,
                data,
            ) catch null;
        };

        const vhea = v: {
            const data = raw_tables.vhea orelse break :v null;
            break :v tables.vhea.Table.parse(data) catch null;
        };
        const vmtx = t: {
            const data = raw_tables.vmtx orelse break :t null;
            break :t tables.hmtx.Table.parse(
                (vhea orelse break :t null).number_of_metrics,
                maxp.number_of_glyphs,
                data,
            ) catch null;
        };

        const loca = t: {
            const data = raw_tables.loca orelse break :t null;
            break :t tables.loca.Table.parse(
                maxp.number_of_glyphs,
                head.index_to_location_format,
                data,
            ) catch null;
        };

        const glyf = t: {
            const loca_table = loca orelse break :t null;
            const data = raw_tables.glyf orelse break :t null;
            break :t tables.glyf.Table.parse(loca_table, data);
        };

        const bdat = b: {
            const bloc_data = raw_tables.bloc orelse break :b null;
            const bloc = tables.cblc.Table.parse(bloc_data);
            const data = raw_tables.bdat orelse break :b null;
            break :b tables.cbdt.Table.parse(bloc, data);
        };

        const cbdt = c: {
            const cblc_data = raw_tables.cblc orelse break :c null;
            const cblc = tables.cblc.Table.parse(cblc_data);
            const data = raw_tables.cbdt orelse break :c null;
            break :c tables.cbdt.Table.parse(cblc, data);
        };

        const ebdt = e: {
            const eblc_data = raw_tables.eblc orelse break :e null;
            const eblc = tables.cblc.Table.parse(eblc_data);
            const data = raw_tables.ebdt orelse break :e null;
            break :e tables.cbdt.Table.parse(eblc, data);
        };

        const cpal = c: {
            const data = raw_tables.cpal orelse break :c null;
            break :c tables.cpal.Table.parse(data) catch null;
        };

        const colr = c: {
            const cpal_table = cpal orelse break :c null;
            const data = raw_tables.colr orelse break :c null;
            break :c tables.colr.Table.parse(cpal_table, data) catch null;
        };

        return .{
            .head = head,
            .hhea = hhea,
            .maxp = maxp,

            .bdat = bdat,
            .cbdt = cbdt,
            .cff = c: {
                const data = raw_tables.cff orelse break :c null;
                break :c tables.cff1.Table.parse_with_upem(
                    data,
                    head.units_per_em,
                ) catch null;
            },
            .cmap = c: {
                const data = raw_tables.cmap orelse break :c null;
                break :c tables.cmap.Table.parse(data) catch null;
            },
            .colr = colr,
            .ebdt = ebdt,
            .glyf = glyf,
            .hmtx = hmtx,
            .kern = k: {
                const data = raw_tables.kern orelse break :k null;
                break :k tables.kern.Table.parse(data) catch null;
            },
            .name = n: {
                const data = raw_tables.name orelse break :n null;
                break :n tables.name.Table.parse(data) catch null;
            },
            .os2 = o: {
                const data = raw_tables.os2 orelse break :o null;
                break :o tables.os2.Table.parse(data) catch null;
            },
            .post = p: {
                const data = raw_tables.post orelse break :p null;
                break :p tables.post.Table.parse(data) catch null;
            },
            .sbix = s: {
                const data = raw_tables.sbix orelse break :s null;
                break :s tables.sbix.Table.parse(
                    maxp.number_of_glyphs,
                    data,
                ) catch null;
            },
            .stat = s: {
                const data = raw_tables.stat orelse break :s null;
                break :s tables.stat.Table.parse(data) catch null;
            },
            .svg = s: {
                const data = raw_tables.svg orelse break :s null;
                break :s tables.svg.Table.parse(data) catch null;
            },
            .vhea = vhea,
            .vmtx = vmtx,
            .vorg = v: {
                const data = raw_tables.vorg orelse break :v null;
                break :v tables.vorg.Table.parse(data) catch null;
            },
            .opentype_layout = if (cfg.opentype_layout) .{
                .gdef = g: {
                    const data = raw_tables.opentype_layout.gdef orelse break :g null;
                    break :g tables.gdef.Table.parse(data) catch null;
                },
                .gpos = g: {
                    const data = raw_tables.opentype_layout.gpos orelse break :g null;
                    break :g opentype_layout.LayoutTable.parse(data) catch null;
                },
                .gsub = g: {
                    const data = raw_tables.opentype_layout.gsub orelse break :g null;
                    break :g opentype_layout.LayoutTable.parse(data) catch null;
                },
                .math = m: {
                    const data = raw_tables.opentype_layout.math orelse break :m null;
                    break :m tables.math.Table.parse(data) catch null;
                },
            },
            .apple_layout = if (cfg.apple_layout) .{
                .ankr = a: {
                    const data = raw_tables.apple_layout.ankr orelse break :a null;
                    break :a tables.ankr.Table.parse(
                        maxp.number_of_glyphs,
                        data,
                    ) catch null;
                },
                .feat = f: {
                    const data = raw_tables.apple_layout.feat orelse break :f null;
                    break :f tables.feat.Table.parse(data) catch null;
                },
                .kerx = k: {
                    const data = raw_tables.apple_layout.kerx orelse break :k null;
                    break :k tables.kerx.Table.parse(
                        maxp.number_of_glyphs,
                        data,
                    ) catch null;
                },
                .morx = m: {
                    const data = raw_tables.apple_layout.morx orelse break :m null;
                    break :m tables.morx.Table.parse(
                        maxp.number_of_glyphs,
                        data,
                    ) catch null;
                },
                .trak = t: {
                    const data = raw_tables.apple_layout.trak orelse break :t null;
                    break :t tables.trak.Table.parse(data) catch null;
                },
            },
            .variable_fonts = if (cfg.variable_fonts) .{
                .avar = a: {
                    const data = raw_tables.variable_fonts.avar orelse break :a null;
                    break :a tables.avar.Table.parse(data) catch null;
                },
                .cff2 = c: {
                    const data = raw_tables.variable_fonts.cff2 orelse break :c null;
                    break :c tables.cff2.Table.parse(data) catch null;
                },
                .fvar = f: {
                    const data = raw_tables.variable_fonts.fvar orelse break :f null;
                    break :f tables.fvar.Table.parse(data) catch null;
                },
                .gvar = g: {
                    const data = raw_tables.variable_fonts.gvar orelse break :g null;
                    break :g tables.gvar.Table.parse(data) catch null;
                },
                .hvar = h: {
                    const data = raw_tables.variable_fonts.hvar orelse break :h null;
                    break :h tables.hvar.Table.parse(data) catch null;
                },
                .mvar = m: {
                    const data = raw_tables.variable_fonts.mvar orelse break :m null;
                    break :m tables.mvar.Table.parse(data) catch null;
                },
                .vvar = v: {
                    const data = raw_tables.variable_fonts.vvar orelse break :v null;
                    break :v tables.vvar.Table.parse(data) catch null;
                },
            },
        };
    }

    /// Creates a new [`Face`] from provided [`RawFaceTables`].
    ///
    /// Does not create a `['RawFace']
    pub fn from_raw_tables(
        raw_tables: RawFaceTables,
    ) FaceParsingError!Face {
        var face: Face = .{
            .raw_face = .{ .data = &.{}, .table_records = .{} },
            .coordinates = if (cfg.variable_fonts) .{},
            .tables = try Face.parse_tables(raw_tables),
        };

        if (cfg.variable_fonts) if (face.tables.variable_fonts.fvar) |fvar| {
            face.coordinates.len = @min(fvar.axes.len(), MAX_VAR_COORDS);
        };

        return face;
    }

    /// Returns a list of names.
    ///
    /// Contains face name and other strings.
    pub fn names(
        self: Face,
    ) tables.name.Names {
        const t: tables.name.Table = self.tables.name orelse .{};
        return t.names;
    }

    /// Returns face style.
    pub fn style(
        self: Face,
    ) tables.os2.Style {
        const t = self.tables.os2 orelse return .normal;
        return t.style();
    }

    /// Checks that face is marked as *Regular*.
    ///
    /// Returns `true` when OS/2 table is not present.
    pub fn is_regular(
        self: Face,
    ) bool {
        return self.style() == .normal;
    }

    /// Checks that face is marked as *Italic*.
    pub fn is_italic(
        self: Face,
    ) bool {
        // A face can have a Normal style and a non-zero italic angle, which also makes it italic.
        return self.style() == .italic or self.italic_angle() != 0.0;
    }

    /// Returns face's italic angle.
    ///
    /// Returns `0.0` when `post` table is not present.
    pub fn italic_angle(
        self: Face,
    ) f32 {
        const t = self.tables.post orelse return 0.0;
        return t.italic_angle;
    }

    /// Checks that face is marked as *Bold*.
    ///
    /// Returns `false` when OS/2 table is not present.
    pub fn is_bold(
        self: Face,
    ) bool {
        const t = self.tables.os2 orelse return false;
        return t.is_bold();
    }

    /// Checks that face is marked as *Oblique*.
    ///
    /// Returns `false` when OS/2 table is not present or when its version is < 4.
    pub fn is_oblique(
        self: Face,
    ) bool {
        return self.style() == .oblique;
    }

    /// Checks that face is marked as *Monospaced*.
    ///
    /// Returns `false` when `post` table is not present.
    pub fn is_monospaced(
        self: Face,
    ) bool {
        const t = self.tables.post orelse return false;
        return t.is_monospaced;
    }

    /// Checks that face is variable.
    ///
    /// Simply checks the presence of a `fvar` table.
    /// returns 'false' if variable_fonts is not enabled
    pub fn is_variable(
        self: Face,
    ) bool {
        if (cfg.variable_fonts) {
            // `fvar::Table::parse` already checked that `axisCount` is non-zero.
            return self.tables.variable_fonts.fvar != null;
        } else return false;
    }

    /// Returns face's weight.
    ///
    /// Returns `Weight::Normal` when OS/2 table is not present.
    pub fn weight(
        self: Face,
    ) tables.os2.Weight {
        const t = self.tables.os2 orelse return .normal;
        return t.weight();
    }

    /// Returns face's width.
    ///
    /// Returns `Width::Normal` when OS/2 table is not present or when value is invalid.
    pub fn width(
        self: Face,
    ) tables.os2.Width {
        const t = self.tables.os2 orelse return .normal;
        return t.width();
    }

    // Read https://github.com/freetype/freetype/blob/49270c17011491227ec7bd3fb73ede4f674aa065/src/sfnt/sfobjs.c#L1279
    // to learn more about the logic behind the following functions.

    /// Returns a horizontal face ascender.
    ///
    /// This method is affected by variation axes.
    pub fn ascender(
        self: Face,
    ) i16 {
        if (self.tables.os2) |os2| if (os2.use_typographic_metrics()) {
            const value = os2.typographic_ascender();
            return self.apply_metrics_variation(Tag.from_bytes("hasc"), value);
        };

        var value = self.tables.hhea.ascender;

        if (value == 0) if (self.tables.os2) |os2| {
            value = os2.typographic_ascender();
            if (value == 0) {
                value = os2.windows_ascender();
                value = self.apply_metrics_variation(Tag.from_bytes("hcla"), value);
            } else {
                value = self.apply_metrics_variation(Tag.from_bytes("hasc"), value);
            }
        };

        return value;
    }

    /// Returns a horizontal face descender.
    ///
    /// This method is affected by variation axes.
    pub fn descender(
        self: Face,
    ) i16 {
        if (self.tables.os2) |os2| if (os2.use_typographic_metrics()) {
            const value = os2.typographic_descender();
            return self.apply_metrics_variation(Tag.from_bytes("hdsc"), value);
        };

        var value = self.tables.hhea.descender;

        if (value == 0) if (self.tables.os2) |os2| {
            value = os2.typographic_descender();
            if (value == 0) {
                value = os2.windows_descender();
                value = self.apply_metrics_variation(Tag.from_bytes("hcld"), value);
            } else {
                value = self.apply_metrics_variation(Tag.from_bytes("hdsc"), value);
            }
        };

        return value;
    }

    /// Returns face's height.
    ///
    /// This method is affected by variation axes.
    pub fn height(
        self: Face,
    ) i16 {
        return self.ascender() - self.descender();
    }

    /// Returns a horizontal face line gap.
    ///
    /// This method is affected by variation axes.
    pub fn line_gap(
        self: Face,
    ) i16 {
        if (self.tables.os2) |os2| if (os2.use_typographic_metrics()) {
            const value = os2.typographic_line_gap();
            return self.apply_metrics_variation(Tag.from_bytes("hlgp"), value);
        };

        var value = self.tables.hhea.line_gap;

        // For line gap, we have to check that ascender or descender are 0, not line gap itself.
        if (self.tables.hhea.ascender == 0 or self.tables.hhea.descender == 0)
            if (self.tables.os2) |os2| {
                if (os2.typographic_ascender() != 0 or os2.typographic_descender() != 0) {
                    value = os2.typographic_line_gap();
                    value = self.apply_metrics_variation(Tag.from_bytes("hlgp"), value);
                } else value = 0;
            };

        return value;
    }

    /// Returns a horizontal typographic face ascender.
    ///
    /// Prefer `Face.ascender` unless you explicitly want this. This is a more
    /// low-level alternative.
    ///
    /// This method is affected by variation axes.
    ///
    /// Returns `null` when OS/2 table is not present.
    pub fn typographic_ascender(
        self: Face,
    ) ?i16 {
        const os2 = self.tables.os2 orelse return null;
        const v = os2.typographic_ascender();
        return self.apply_metrics_variation(Tag.from_bytes("hasc"), v);
    }

    /// Returns a horizontal typographic face descender.
    ///
    /// Prefer `Face.descender` unless you explicitly want this. This is a more
    /// low-level alternative.
    ///
    /// This method is affected by variation axes.
    ///
    /// Returns `null` when OS/2 table is not present.
    pub fn typographic_descender(
        self: Face,
    ) ?i16 {
        const os2 = self.tables.os2 orelse return null;
        const v = os2.typographic_descender();
        return self.apply_metrics_variation(Tag.from_bytes("hdsc"), v);
    }

    /// Returns a horizontal typographic face line gap.
    ///
    /// Prefer `Face.line_gap` unless you explicitly want this. This is a more
    /// low-level alternative.
    ///
    /// This method is affected by variation axes.
    ///
    /// Returns `null` when OS/2 table is not present.
    pub fn typographic_line_gap(
        self: Face,
    ) ?i16 {
        const os2 = self.tables.os2 orelse return null;
        const v = os2.typographic_line_gap();
        return self.apply_metrics_variation(Tag.from_bytes("hlgp"), v);
    }

    /// Returns a vertical face ascender.
    ///
    /// This method is affected by variation axes.
    pub fn vertical_ascender(
        self: Face,
    ) ?i16 {
        const vhea = self.tables.vhea orelse return null;
        const v = vhea.ascender;
        return self.apply_metrics_variation(Tag.from_bytes("vasc"), v);
    }

    /// Returns a vertical face descender.
    ///
    /// This method is affected by variation axes.
    pub fn vertical_descender(
        self: Face,
    ) ?i16 {
        const vhea = self.tables.vhea orelse return null;
        const v = vhea.descender;
        return self.apply_metrics_variation(Tag.from_bytes("vdsc"), v);
    }

    /// Returns a vertical face height.
    ///
    /// This method is affected by variation axes.
    pub fn vertical_height(
        self: Face,
    ) ?i16 {
        const a = self.vertical_ascender() orelse return null;
        const d = self.vertical_descender() orelse return null;
        return a + d;
    }

    /// Returns a vertical face line gap.
    ///
    /// This method is affected by variation axes.
    pub fn vertical_line_gap(
        self: Face,
    ) ?i16 {
        const vhea = self.tables.vhea orelse return null;
        const v = vhea.line_gap;
        return self.apply_metrics_variation(Tag.from_bytes("vlgp"), v);
    }

    /// Returns face's units per EM.
    ///
    /// Guarantee to be in a 16..=16384 range.
    pub fn units_per_em(
        self: Face,
    ) u16 {
        return self.tables.head.units_per_em;
    }

    /// Returns face's x height.
    ///
    /// This method is affected by variation axes.
    ///
    /// Returns `null` when OS/2 table is not present or when its version is < 2.
    pub fn x_height(
        self: Face,
    ) ?i16 {
        const os2 = self.tables.os2 orelse return null;
        const v = os2.x_height() orelse return null;
        return self.apply_metrics_variation(Tag.from_bytes("xhgt"), v);
    }

    /// Returns face's capital height.
    ///
    /// This method is affected by variation axes.
    ///
    /// Returns `null` when OS/2 table is not present or when its version is < 2.
    pub fn capital_height(
        self: Face,
    ) ?i16 {
        const os2 = self.tables.os2 orelse return null;
        const v = os2.capital_height() orelse return null;
        return self.apply_metrics_variation(Tag.from_bytes("cpht"), v);
    }

    fn apply_metrics_variation(
        self: Face,
        tag: u32,
        value_immutable: i16,
    ) i16 {
        var value = value_immutable;
        if (cfg.variable_fonts) if (self.is_variable()) {
            const metrics: f32 = m: {
                const mvar = self.tables.variable_fonts.mvar orelse break :m 0.0;
                break :m mvar.metric_offset(tag, self.coords()) orelse 0.0;
            };
            const v: f32 = @as(f32, @floatFromInt(value)) + metrics;
            // TODO: Should probably round it, but f32::round is not available in core.
            value = f32_to_i16(v) orelse value;
        };

        return value;
    }

    fn coords(
        self: Face,
    ) []const NormalizedCoordinate {
        return self.coordinates.data[0..self.coordinates.len];
    }
};

/// A raw font face.
///
/// You are probably looking for [`Face`]. This is a low-level type.
///
/// Unlike [`Face`], [`RawFace`] parses only face table records.
/// Meaning all you can get from this type is a raw (`[]const u8`) data of a requested table.
/// Then you can either parse just a singe table from a font/face or populate [`RawFaceTables`]
/// manually before passing it to [`Face.from_raw_tables`].
pub const RawFace = struct {
    /// The input font file data.
    data: []const u8,
    /// An array of table records.
    table_records: LazyArray16(TableRecord),

    const Self = @This();

    /// Creates a new [`RawFace`] from a raw data.
    ///
    /// `index` indicates the specific font face in a font collection.
    /// Use [`fonts_in_collection`] to get the total number of font faces.
    /// Set to 0 if unsure.
    ///
    /// While we do reuse [`FaceParsingError`], `No*Table` errors will not be throws.
    pub fn parse(
        data: []const u8,
        index: u32,
    ) FaceParsingError!Self {
        var s = parser.Stream.new(data);
        const magic = s.read(Magic) catch return error.UnknownMagic;
        switch (magic) {
            .font_collection => {
                s.skip(u32); // version
                const number_of_faces = s.read(u32) catch
                    return error.MalformedFont;

                const offsets = s.read_array(parser.Offset32, number_of_faces) catch
                    return error.MalformedFont;

                const face_offset = offsets.get(index) orelse
                    return error.FaceIndexOutOfBounds;

                // Face offset is from the start of the font data,
                // so we have to adjust it to the current parser offset.
                const offset = std.math.sub(usize, face_offset[0], s.offset) catch
                    return error.MalformedFont;

                s.advance_checked(offset) catch return error.MalformedFont;

                // Read **face** magic.
                // Each face in a font collection also starts with a magic.
                const face_magic = s.read(Magic) catch return error.UnknownMagic;
                // And face in a font collection can't be another collection.
                if (face_magic == .font_collection) return error.UnknownMagic;
            },
            // When reading from a regular font (not a collection) disallow index to be non-zero
            // Basically treat the font as a one-element collection
            else => if (index != 0) return error.FaceIndexOutOfBounds,
        }

        const num_tables = s.read(u16) catch return error.MalformedFont;
        s.advance(6); // searchRange (u16) + entrySelector (u16) + rangeShift (u16)

        const table_records = s.read_array(TableRecord, num_tables) catch
            return error.MalformedFont;

        return .{
            .data = data,
            .table_records = table_records,
        };
    }

    /// Returns the raw data of a selected table.
    pub fn table(
        self: Self,
        tag: Tag,
    ) ?[]const u8 {
        const func = struct {
            fn func(record: TableRecord, t: Tag) std.math.Order {
                const lhs = record.tag.inner;
                const rhs = t.inner;

                return std.math.order(lhs, rhs);
            }
        }.func;

        _, const table_v = self.table_records.binary_search_by(tag, func) orelse return null;

        const offset = table_v.offset;
        const length = table_v.length;
        const end = std.math.add(usize, offset, length) catch return null;

        if (offset > self.data.len or end > self.data.len) return null;
        return self.data[offset..end];
    }
};

/// Parsed face tables.
///
/// Unlike [`Face`], provides a low-level parsing abstraction over TrueType tables.
/// Useful when you need a direct access to tables data.
///
/// Also, used when high-level API is problematic to implement.
/// A good example would be OpenType layout tables (GPOS/GSUB).
pub const FaceTables = struct {
    // Mandatory tables.
    head: tables.head.Table,
    hhea: tables.hhea.Table,
    maxp: tables.maxp.Table,

    bdat: ?tables.cbdt.Table = null,
    cbdt: ?tables.cbdt.Table = null,
    cff: ?tables.cff1.Table = null,
    cmap: ?tables.cmap.Table = null,
    colr: ?tables.colr.Table = null,
    ebdt: ?tables.cbdt.Table = null,
    glyf: ?tables.glyf.Table = null,
    hmtx: ?tables.hmtx.Table = null,
    kern: ?tables.kern.Table = null,
    name: ?tables.name.Table = null,
    os2: ?tables.os2.Table = null,
    post: ?tables.post.Table = null,
    sbix: ?tables.sbix.Table = null,
    stat: ?tables.stat.Table = null,
    svg: ?tables.svg.Table = null,
    vhea: ?tables.vhea.Table = null,
    vmtx: ?tables.hmtx.Table = null,
    vorg: ?tables.vorg.Table = null,

    opentype_layout: if (cfg.opentype_layout) struct {
        gdef: ?tables.gdef.Table = null,
        gpos: ?opentype_layout.LayoutTable = null,
        gsub: ?opentype_layout.LayoutTable = null,
        math: ?tables.math.Table = null,
    } else void,

    apple_layout: if (cfg.apple_layout) struct {
        ankr: ?tables.ankr.Table = null,
        feat: ?tables.feat.Table = null,
        kerx: ?tables.kerx.Table = null,
        morx: ?tables.morx.Table = null,
        trak: ?tables.trak.Table = null,
    } else void,

    variable_fonts: if (cfg.variable_fonts) struct {
        avar: ?tables.avar.Table = null,
        cff2: ?tables.cff2.Table = null,
        fvar: ?tables.fvar.Table = null,
        gvar: ?tables.gvar.Table = null,
        hvar: ?tables.hvar.Table = null,
        mvar: ?tables.mvar.Table = null,
        vvar: ?tables.vvar.Table = null,
    } else void,
};

/// A list of all supported tables as raw data.
///
/// This type should be used in tandem with
/// [`Face.from_raw_tables()`](struct.Face.html#method.from_raw_tables).
///
/// This allows loading font faces not only from TrueType font files,
/// but from any source. Mainly used for parsing WOFF.
pub const RawFaceTables = struct {
    // Mandatory tables.
    /// Font Header, global information about the font, version number, creation and modification dates, revision number, and basic typographic data.
    head: []const u8 = &.{},
    /// Horizontal Header, information needed to layout fonts whose characters are written horizontally.
    hhea: []const u8 = &.{},
    /// Maximum Profile, establishes the memory requirements for a font.
    maxp: []const u8 = &.{},

    /// Bitmap data table
    bdat: ?[]const u8 = null,
    /// Bitmap Location, availability of bitmaps at requested point sizes.
    bloc: ?[]const u8 = null,
    /// Color Bitmap Data, used to embed color bitmap glyph data.
    cbdt: ?[]const u8 = null,
    /// Color Bitmap Location, provides locators for embedded color bitmaps.
    cblc: ?[]const u8 = null,
    /// Compact Font Format 1
    cff: ?[]const u8 = null,
    /// Character to Glyph Mapping, maps character codes to glyph indices.
    cmap: ?[]const u8 = null,
    /// Color, adds support for multi-colored glyphs.
    colr: ?[]const u8 = null,
    /// Color Palette, a set of one or more color palettes.
    cpal: ?[]const u8 = null,
    /// Embedded Bitmap Data, embed monochrome or grayscale bitmap glyph data.
    ebdt: ?[]const u8 = null,
    /// Embedded Bitmap Location, provides embedded bitmap locators.
    eblc: ?[]const u8 = null,
    /// Glyph Outline, data that defines the appearance of the glyphs.
    glyf: ?[]const u8 = null,
    /// Horizontal Metrics, metric information for the horizontal layout each of the glyphs.
    hmtx: ?[]const u8 = null,
    /// Kern, values that adjust the intercharacter spacing for glyphs.
    kern: ?[]const u8 = null,
    /// Glyph Data Location, stores the offsets to the locations of the glyphs.
    loca: ?[]const u8 = null,
    /// Font Names, human-readable names for features and settings, copyright, font names, style names, and other information.
    name: ?[]const u8 = null,
    /// OS/2 Compatibility, a set of metrics that are required by Windows.
    os2: ?[]const u8 = null,
    /// Glyph Name and PostScript Font, information needed to use a TrueType font on a PostScript printer.
    post: ?[]const u8 = null,
    /// Extended Bitmaps, provides access to bitmap data in a standard graphics format (such as PNG, JPEG, TIFF).
    sbix: ?[]const u8 = null,
    /// Style Attributes, describes design attributes that distinguish font-style variants within a font family.
    stat: ?[]const u8 = null,
    /// Scalable Vector Graphics, contains SVG descriptions for some or all of the glyphs in the font.
    svg: ?[]const u8 = null,
    /// Vertical Header, information needed for vertical fonts.
    vhea: ?[]const u8 = null,
    /// Vertical Metrics, specifies the vertical spacing for each glyph in an AAT vertical font.
    vmtx: ?[]const u8 = null,
    /// Vertical Origin, the y coordinate of a glyph’s vertical origin, this can only be used in CFF or CFF2 fonts.
    vorg: ?[]const u8 = null,

    opentype_layout: if (cfg.opentype_layout) struct {
        /// Glyph Definition, provides various glyph properties used in OpenType Layout processing.
        gdef: ?[]const u8 = null,
        /// Glyph Positioning, precise control over glyph placement for sophisticated text layout in each supported script.
        gpos: ?[]const u8 = null,
        /// Glyph Substitution, provides data for substitution of glyphs for appropriate rendering of different scripts.
        gsub: ?[]const u8 = null,
        /// Mathematical Typesetting, font-specific information necessary for math formula layout.
        math: ?[]const u8 = null,
    } else void = if (cfg.opentype_layout) .{},

    apple_layout: if (cfg.apple_layout) struct {
        /// Anchor Point Table, defines anchor points.
        ankr: ?[]const u8 = null,
        /// Feature Name Table, font's text features.
        feat: ?[]const u8 = null,
        /// Kerx, extended kerning table.
        kerx: ?[]const u8 = null,
        /// Extended Glyph Metamorphosis, specifies a set of transformations that can apply to the glyphs of your font.
        morx: ?[]const u8 = null,
        /// Tracking, allows AAT fonts to adjust to normal interglyph spacing.
        trak: ?[]const u8 = null,
    } else void = if (cfg.apple_layout) .{},

    variable_fonts: if (cfg.variable_fonts) struct {
        /// Axis Variation Table, allows the font to modify the mapping between axis values and these normalized values.
        avar: ?[]const u8 = null,
        /// Compact Font Format 2
        cff2: ?[]const u8 = null,
        /// Font Variations Table, global information of which variation axes are included in the font.
        fvar: ?[]const u8 = null,
        /// Glyph Variations Table, includes all of the data required for stylizing the glyphs.
        gvar: ?[]const u8 = null,
        /// Horizontal Metrics Variations Table, used in variable fonts to provide glyph variations for horizontal glyph metrics values.
        hvar: ?[]const u8 = null,
        /// Metrics Variations Table, used in variable fonts to provide glyph variations for font-wide metric values found in other font tables.
        mvar: ?[]const u8 = null,
        /// Vertical Metrics Variations Table, used in variable fonts to provide glyph variations for vertical glyph metric values.
        vvar: ?[]const u8 = null,
    } else void = if (cfg.variable_fonts) .{},
};

/// A raw table record.
pub const TableRecord = struct {
    tag: Tag,
    check_sum: u32,
    offset: u32,
    length: u32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 16;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            var s = parser.Stream.new(data);

            return .{
                .tag = try s.read(Tag),
                .check_sum = try s.read(u32),
                .offset = try s.read(u32),
                .length = try s.read(u32),
            };
        }
    };
};

/// A 4-byte tag.
pub const Tag = struct {
    inner: u32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            const u = std.mem.readInt(u32, data, .big);
            return .{ .inner = u };
        }
    };

    /// Creates a `Tag` from bytes.
    pub fn from_bytes(bytes: *const [4]u8) u32 {
        const _0 = @as(u32, bytes[0]) << 24;
        const _1 = @as(u32, bytes[1]) << 16;
        const _2 = @as(u32, bytes[2]) << 8;
        const _3 = @as(u32, bytes[3]);

        return _0 | _1 | _2 | _3;
    }

    /// Returns tag as 4-element byte array.
    pub fn to_bytes(self: Self) [4]u8 {
        return .{
            @truncate((self.inner >> 24 & 0xff)),
            @truncate((self.inner >> 16 & 0xff)),
            @truncate((self.inner >> 8 & 0xff)),
            @truncate((self.inner >> 0 & 0xff)),
        };
    }
};

/// A list of font face parsing errors.
pub const FaceParsingError = error{
    /// An attempt to read out of bounds detected.
    ///
    /// Should occur only on malformed fonts.
    MalformedFont,

    /// Face data must start with `0x00010000`, `0x74727565`, `0x4F54544F` or `0x74746366`.
    UnknownMagic,

    /// The face index is larger than the number of faces in the font.
    FaceIndexOutOfBounds,

    /// The `head` table is missing or malformed.
    NoHeadTable,

    /// The `hhea` table is missing or malformed.
    NoHheaTable,

    /// The `maxp` table is missing or malformed.
    NoMaxpTable,
};

/// A rectangle.
///
/// Doesn't guarantee that `x_min` <= `x_max` and/or `y_min` <= `y_max`.
pub const Rect = struct {
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

/// A line metrics.
///
/// Used for underline and strikeout.
pub const LineMetrics = struct {
    /// Line position.
    position: i16,
    /// Line thickness.
    thickness: i16,
};

/// A TrueType font magic.
///
/// https://docs.microsoft.com/en-us/typography/opentype/spec/otff#organization-of-an-opentype-font
pub const Magic = enum {
    true_type,
    open_type,
    font_collection,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) parser.Error!Self {
            const u = std.mem.readInt(u32, data, .big);
            switch (u) {
                0x00010000, 0x74727565 => return .true_type,
                0x4F54544F => return .open_type,
                0x74746366 => return .font_collection,
                else => return error.ParseFail,
            }
        }
    };
};

// VARIABLE FONTS
// [ARS] These should get compiled out if variable_fonts option is false
const MAX_VAR_COORDS: u7 = 64;
const VarCoords = struct {
    data: [MAX_VAR_COORDS]NormalizedCoordinate = @splat(.{ .inner = 0 }),
    len: u8 = 0,
};

/// A variation coordinate in a normalized coordinate system.
///
/// Basically any number in a -1.0..1.0 range.
/// Where 0 is a default value.
///
/// The number is stored as f2.16
pub const NormalizedCoordinate = struct { inner: i16 };

// [ARS] NUMERICAL STUFF
fn f32_to_i32(v: f32) ?i32 {
    // [ARS] this method is a bastardization of the of source
    const MIN: f32 = @floatFromInt(std.math.minInt(i32));

    // [ARs] https://ziggit.dev/t/determining-lower-upper-bound-for-safe-conversion-from-f32-to-i32/3764/3?u=asibahi
    const MAX_P1: f32 = @floatFromInt(2147483520);

    if (v >= MIN and v <= MAX_P1)
        return @intFromFloat(v)
    else
        return null;
}

fn f32_to_i16(v: f32) ?i16 {
    const i = f32_to_i32(v) orelse return null;
    return std.math.cast(i16, i);
}
