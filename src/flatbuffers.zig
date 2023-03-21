const fb = @import("flatbufferz");

/// a generic helper to initialize a FlatBuffer with
/// the provided buffer at offset
pub fn GetRootAs(buf: []u8, offset: u32, comptime T: type) T {
    const n = fb.encode.read(u32, buf[offset..]);
    return T.init(buf, n + offset);
}

/// retrives the relative offset in the provided buffer stored at `offset`.
pub fn getIndirectOffset(buf: []const u8, offset: u32) u32 {
    return offset + fb.encode.read(u32, buf[offset..][0..4]);
}
