const fb = @import("flatbufferz");

/// a generic helper to initialize a FlatBuffer with
/// the provided buffer at offset
pub fn GetRootAs(comptime T: type, buf: []u8, offset: u32) T {
    const n = fb.encode.read(u32, buf[offset..]);
    return T.init(buf, n + offset);
}

/// a generic helper to initialize a FlatBuffer with the provided size-prefixed buffer
/// bytes and its data offset
pub fn GetSizePrefixedRootAs(comptime T: type, buf: []u8, offset: u32) T {
    const n = fb.encode.read(u32, buf[offset + fb.Builder.size_prefix_length ..]);
    return T.init(buf, n + offset + fb.Builder.size_prefix_length);
}

// read the size from a size-prefixed flatbuffer
pub fn GetSizePrefix(buf: []u8, offset: u32) u32 {
    return fb.encode.read(u32, buf[offset..][0..4]);
}

/// retrives the relative offset in the provided buffer stored at `offset`.
pub fn getIndirectOffset(buf: []const u8, offset: u32) u32 {
    return offset + fb.encode.read(u32, buf[offset..][0..4]);
}
