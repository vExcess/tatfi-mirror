/// A slice-like container that converts internal binary data only on access.
///
/// Array values are stored in a continuous data chunk.
// [ARS] Currently a placeholder
pub fn LazyArray16(T: type) type {
    return struct {
        data_type: T, // core::marker::PhantomData<T>,
        data: []u8,
    };
}
