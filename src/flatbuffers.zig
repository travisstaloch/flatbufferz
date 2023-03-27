const std = @import("std");
const fb = @import("flatbufferz");

/// a generic helper to initialize a FlatBuffer with the provided buffer at offset
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
pub fn GetIndirectOffset(buf: []const u8, offset: u32) u32 {
    return offset + fb.encode.read(u32, buf[offset..][0..4]);
}

/// Extract the file_identifier from a buffer
pub fn GetBufferIdentifier(
    buf: []const u8,
    offset_: u32,
    size_prefixed: bool,
) *const [fb.Builder.file_identifier_len]u8 {
    var offset = offset_;
    if (size_prefixed) {
        // increase offset by size of u32
        offset += fb.Builder.size_u32;
    }
    // increase offset by size of root table pointer
    offset += fb.Builder.size_u32;
    // end of FILE_IDENTIFIER
    return buf[offset..][0..fb.Builder.file_identifier_len];
}

pub fn BufferHasIdentifier(
    buf: []const u8,
    offset: u32,
    file_identifier: [fb.Builder.file_identifier_len]u8,
    size_prefixed: bool,
) bool {
    const fid = GetBufferIdentifier(buf, offset, size_prefixed);
    return std.mem.eql(u8, fid, &file_identifier);
}
