/// A slice-like container that converts internal binary data only on access.
///
/// Array values are stored in a continuous data chunk.
// [ARS] Currently a stub
pub fn LazyArray16(T: type) type {
    // [ARS] T implements trait FromData
    return struct {
        data_type: T, // core::marker::PhantomData<T>,
        data: []const u8,
    };
}

/// A slice-like container that converts internal binary data only on access.
///
/// This is a low-level, internal structure that should not be used directly.
// [ARS] Currently a stub
pub fn LazyArray32(T: type) type {
    // [ARS] T implements trait FromData
    return struct {
        data_type: T, // core::marker::PhantomData<T>,
        data: []const u8,
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
        // Zero offsets must be ignored, therefore we're using `Option<Offset16>`.
        offsets: LazyArray16(?Offset16),
        data_type: T, // core::marker::PhantomData<T>,
    };
}

/// A type-safe u32 offset.
pub const Offset32 = struct { u32 };

/// A type-safe u24 offset.
pub const Offset24 = struct { u24 };

/// A type-safe u16 offset.
pub const Offset16 = struct { u16 };

/// A 16-bit signed fixed number with the low 14 bits of fraction (2.14).
pub const F2DOT14 = struct { i16 };

/// A 32-bit signed fixed-point number (16.16).
pub const Fixed = struct { f32 };
