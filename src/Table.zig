//! 
//! A port of https://github.com/google/flatbuffers/blob/master/go/table.go
//! 

const std = @import("std");
const encode = @import("encode.zig");
const Builder = @import("Builder.zig");
const size_u32 = Builder.size_u32;
const Table = @This();

bytes: []const u8,
pos: u32, // Always < 1<<31.

pub const Struct = struct {
    _tab: Table,

    pub fn init(bytes: []const u8, pos: u32) Struct {
        return .{ ._tab = .{ .bytes = bytes, .pos = pos } };
    }
};

pub fn init(bytes: []const u8, pos: u32) Table {
    return .{ .bytes = bytes, .pos = pos };
}

/// provides access into the Table's vtable.
///
/// Fields which are deprecated are ignored by checking against the vtable's length.
pub fn offset(t: Table, vtable_offset: u16) u16 {
    const vtable = @bitCast(u32, @bitCast(i32, t.pos) - t.read(i32, t.pos));
    if (vtable_offset < t.read(u16, vtable)) {
        return t.read(u16, vtable + vtable_offset);
    }
    return 0;
}

pub fn readWithDefault(t: Table, comptime T: type, comptime off: u32, comptime default: T) T {
    const o = t.offset(off);
    return if (o != 0)
        t.read(T, o + t.pos)
    else
        default;
}

pub fn readByteVectorWithDefault(t: Table, comptime off: u32, comptime default: []const u8) []const u8 {
    const o = t.offset(off);
    return if (o != 0)
        t.byteVector(o + t.pos)
    else
        default;
}

/// retrieves the relative offset stored at `offset`.
pub fn indirect(t: Table, off: u32) u32 {
    return off + t.read(u32, off);
}

/// gets a byte slice from data stored inside the flatbuffer.
pub fn byteVector(t: Table, off_: u32) []const u8 {
    const off = off_ + t.read(u32, off_);
    const start = off + size_u32;
    const length = t.read(u32, off);
    std.log.debug("start={} length={} bytes.len={} off={}", .{ start, length, t.bytes.len, off });
    return t.bytes[start .. start + length];
}

/// retrieves the length of the vector whose offset is stored at
/// "off" in this object.
pub fn vectorLen(t: Table, off_: u32) u32 {
    var off = off_ + t.pos;
    off += t.read(u32, off);
    return t.read(u32, off);
}

/// retrieves the length of the vector whose offset is stored at
/// "off" in this object. returns 0 if not found.
pub fn readVectorLen(t: Table, comptime off: u32) u32 {
    const o = t.offset(off);
    return if (o != 0)
        t.vectorLen(o)
    else
        0;
}

/// retrieves the start of data of the vector whose offset is stored
/// at "off" in this object.
pub fn vector(t: Table, off_: u32) u32 {
    const off = off_ + t.pos;
    const x = off + t.read(u32, off);
    // data starts after metadata containing the vector length
    return x + size_u32;
}

/// initializes any Table-derived type to point to the union at the given
/// offset.
pub fn union_(t: Table, off_: u32) Table {
    const off = off_ + t.pos;
    return .{
        .pos = off + t.read(u32, off),
        .bytes = t.bytes,
    };
}

/// reads a T from t.bytes starting at "off". supports float and int Ts
pub fn read(t: Table, comptime T: type, off: u32) T {
    return encode.read(T, t.bytes[off..]);
}
