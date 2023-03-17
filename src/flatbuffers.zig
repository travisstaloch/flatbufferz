const fb = @import("flatbufferz");

/// a generic helper to initialize a FlatBuffer with
/// the provided buffer at offset
pub fn GetRootAs(buf: []const u8, offset: u32, comptime T: type) T {
    const n = fb.encode.read(u32, buf[offset..]);
    return T.init(buf, n + offset);
}
