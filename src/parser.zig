const std = @import("std");

/// A slice-like container that converts internal binary data only on access.
///
/// Array values are stored in a continuous data chunk.
pub fn LazyArray16(T: type) type {
    return LazyArray(u16, T);
}
/// A slice-like container that converts internal binary data only on access.
///
/// Array values are stored in a continuous data chunk.
pub fn LazyArray32(T: type) type {
    return LazyArray(u32, T);
}

/// A slice-like container that converts internal binary data only on access.
///
/// This is a low-level, internal structure that should not be used directly.
pub fn LazyArray(I: type, T: type) type {
    // [ARS] T implements trait FromData

    std.debug.assert(I == u8 or I == u16 or I == u32);
    return struct {
        data: []const u8 = &.{},

        const Self = @This();

        pub fn new(
            data: []const u8,
        ) Self {
            return .{ .data = data };
        }

        /// Returns a value at `index`.
        pub fn get(
            self: Self,
            index: I,
        ) ?T {
            const size: usize = switch (has_trait(T, "FromData")) {
                .int => @typeInfo(T).int.bits / 8,
                .wrapper => |F| @typeInfo(F).int.bits / 8,
                .impl => T.FromData.SIZE,
            };

            if (index >= self.len()) return null;
            const start: usize = index * size;
            if (start > self.data.len) return null;
            if (start + size > self.data.len) return null;

            const bytes: *const [size]u8 = self.data[start..][0..size];
            return switch (has_trait(T, "FromData")) {
                .int => std.mem.readInt(T, bytes, .big),
                .wrapper => |F| .{std.mem.readInt(F, bytes, .big)},
                .impl => T.FromData.parse(bytes) catch return null,
            };
        }

        /// Returns array's length.
        pub fn len(
            self: Self,
        ) I {
            const size: usize = switch (has_trait(T, "FromData")) {
                .int => @typeInfo(T).int.bits / 8,
                .wrapper => |F| @typeInfo(F).int.bits / 8,
                .impl => T.FromData.SIZE,
            };

            return @truncate(self.data.len / size);
        }

        pub fn iterator(
            data: *const Self,
        ) Self.Iterator {
            return .{ .data = data };
        }

        pub const Iterator = struct {
            data: *const Self,
            index: I = 0,

            pub fn next(
                self: *Iterator,
            ) ?T {
                defer self.index += 1;
                return self.data.get(self.index);
            }
        };
    };
}

/// A [`LazyArray16`]-like container, but data is accessed by offsets.
///
/// Unlike [`LazyArray16`], internal storage is not continuous.
///
/// Multiple offsets can point to the same data.
// [ARS] Currently a stub
pub fn LazyOffsetArray16(T: type) type {
    // [ARS] T implements trait FromSlice
    return struct {
        data: []const u8,
        // Zero offsets must be ignored, therefore we're using `NonZeroOffset16`.
        offsets: LazyArray16(NonZeroOffset16),
        data_type: T, // core::marker::PhantomData<T>,
    };
}

/// A type-safe u32 offset.
pub const Offset32 = struct { u32 };

/// A type-safe u32 optional offset. Replacement for Option<Offset32> in Rust.
pub const NonZeroOffset32 = struct { u32 };

/// A type-safe u24 offset.
pub const Offset24 = struct { u24 };

/// A type-safe u24 optional offset. Replacement for Option<Offset24> in Rust.
pub const NonZeroOffset24 = struct { u24 };

/// A type-safe u16 offset.
pub const Offset16 = struct { u16 };

/// A type-safe u16 optional offset. Replacement for Option<Offset16> in Rust.
pub const NonZeroOffset16 = struct { u16 };

/// A 16-bit signed fixed number with the low 14 bits of fraction (2.14).
pub const F2DOT14 = struct { i16 };

/// A 32-bit signed fixed-point number (16.16).
pub const Fixed = struct {
    value: f32,

    const Self = @This();
    pub const FromData = struct {
        // [ARS] impl of FromData trait
        pub const SIZE: usize = 4;

        pub fn parse(
            data: *const [SIZE]u8,
        ) Error!Self {
            const i = std.mem.readInt(i32, data, .big);
            const f: f32 = @floatFromInt(i);
            return .{ .value = f / (1 << 16) };
        }
    };
};

/// A streaming binary parser.
pub const Stream = struct {
    data: []const u8,
    offset: usize,

    /// Creates a new `Stream` parser.
    pub fn new(
        data: []const u8,
    ) Stream {
        return .{ .data = data, .offset = 0 };
    }

    /// Creates a new `Stream` parser at offset.
    ///
    /// Returns an error when `offset` is out of bounds.
    pub fn new_at(
        data: []const u8,
        offset: usize,
    ) Error!Stream {
        return if (offset <= data.len)
            .{ .data = data, .offset = offset }
        else
            error.ParseFail;
    }

    /// Parses the type from the steam.
    ///
    /// Returns an error when there is not enough data left in the stream
    /// or the type parsing failed.
    pub fn read(
        self: *Stream,
        T: type,
    ) Error!T {
        const size: usize = switch (has_trait(T, "FromData")) {
            .int => @typeInfo(T).int.bits / 8,
            .wrapper => |F| @typeInfo(F).int.bits / 8,
            .impl => T.FromData.SIZE,
        };

        const bytes = try self.read_bytes(size);

        return switch (has_trait(T, "FromData")) {
            .int => std.mem.readInt(T, bytes[0..size], .big),
            .wrapper => |F| .{std.mem.readInt(F, bytes[0..size], .big)},
            .impl => try T.FromData.parse(bytes[0..size]),
        };
    }

    /// Parses the type from the steam at offset.
    pub fn read_at(
        self: *Stream,
        T: type,
        offset: usize,
    ) Error!T {
        // [ARS] different impl from Rust's
        self.offset = offset;
        return try self.read(T);
    }

    /// Reads N bytes from the stream.
    pub fn read_bytes(
        self: *Stream,
        len: usize,
    ) Error![]const u8 {
        // An integer overflow here on 32bit systems is almost guarantee to be caused
        // by an incorrect parsing logic from the caller side.
        // Simply using `checked_add` here would silently swallow errors, which is not what we want.
        std.debug.assert(self.offset + len <= std.math.maxInt(u32));

        const start = self.offset + len;
        if (start > self.data.len) return error.ParseFail;
        const end = start + len;
        if (end > self.data.len) return error.ParseFail;

        defer self.advance(len);
        return self.data[start..end];
    }

    /// Reads the next `count` types as a slice.
    pub fn read_array(
        self: *Stream,
        T: type,
        // u16 or u32
        count: anytype,
    ) Error!LazyArray(@TypeOf(count), T) {
        const size: usize = switch (has_trait(T, "FromData")) {
            .int => @typeInfo(T).int.bits / 8,
            .wrapper => |F| @typeInfo(F).int.bits / 8,
            .impl => T.FromData.SIZE,
        };

        const len = count * size;

        const bytes = try self.read_bytes(len);

        return LazyArray(@TypeOf(count), T).new(bytes);
    }

    /// Parses the `count` types as a slice from the steam at offset.
    pub fn read_array_at(
        self: *Stream,
        T: type,
        count: anytype,
        offset: usize,
    ) Error!LazyArray(@TypeOf(count), T) {
        self.offset = offset;
        return try self.read_array(T, count);
    }

    /// Advances by `FromData::SIZE`.
    ///
    /// Doesn't check bounds.
    pub fn skip(
        self: *Stream,
        T: type,
    ) void {
        const size: usize = switch (has_trait(T, "FromData")) {
            .int => @typeInfo(T).int.bits / 8,
            .wrapper => |F| @typeInfo(F).int.bits / 8,
            .impl => T.FromData.SIZE,
        };

        self.advance(size);
    }

    /// Advances by the specified `len`.
    ///
    /// Doesn't check bounds.
    pub fn advance(
        self: *Stream,
        len: usize,
    ) void {
        self.offset += len;
    }

    /// Advances by the specified `len` and checks for bounds.
    /// return `true` if it advances
    pub fn advance_checked(
        self: *Stream,
        len: usize,
    ) bool {
        if (self.offset + len > self.data.len) return false;

        self.advance(len);
        return true;
    }

    /// Returns the trailing data.
    ///
    /// Returns an error when `Stream` is reached the end.
    pub fn tail(
        self: *Stream,
    ) Error![]const u8 {
        if (self.offset > self.data.len) return error.ParseFail;
        return self.data[self.offset..];
    }

    /// Checks that stream reached the end of the data.
    pub fn at_end(
        self: Stream,
    ) bool {
        return self.offset >= self.data.len;
    }
};

pub const Error = error{
    ParseFail,
    Overflow,
};

inline fn has_trait(
    T: type,
    comptime trait: []const u8,
) union(enum) { int, wrapper: type, impl } {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .int => {
            if (type_info.int.bits % 8 != 0) @compileError(@typeName(T) ++
                " must have bitcount divisble by 8");
            return .int;
        },
        .@"struct" => |s| {
            if (@hasDecl(T, trait)) return .impl;
            if (s.is_tuple and s.fields.len == 1)
                return .{ .wrapper = s.fields[0].type };

            @compileError(@typeName(T) ++ " does not implement trait " ++ trait);
        },
        else => if (@hasDecl(T, trait))
            return .impl
        else
            @compileError(@typeName(T) ++ " does not implement trait " ++ trait),
    }
}
