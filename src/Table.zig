//!
//! A port of https://github.com/google/flatbuffers/blob/master/go/table.go
//!

const std = @import("std");
const fb = @import("flatbufferz");
const Builder = fb.Builder;
const encode = fb.encode;
const size_u32 = Builder.size_u32;
const Table = @This();

bytes: []u8,
pos: u32 = 0, // Always < 1<<31.

pub const Struct = struct {
    _tab: Table,

    pub fn init(bytes: []const u8, pos: u32) Struct {
        return .{ ._tab = .{ .bytes = bytes, .pos = pos } };
    }

    /// reads a T from t.bytes starting at "off". supports float and int Ts
    pub fn read(s: Struct, comptime T: type, off: u32) T {
        return encode.read(T, s._tab.bytes[off..]);
    }
};

pub fn init(bytes: []u8, pos: u32) Table {
    return .{ .bytes = bytes, .pos = pos };
}

pub fn Init(comptime T: type) fn ([]u8, u32) T {
    return struct {
        pub fn func(buf: []u8, i: u32) T {
            return .{ ._tab = Table.init(buf, i) };
        }
    }.func;
}

pub fn GetRootAs(comptime T: type) fn ([]u8, u32) T {
    return struct {
        pub fn func(buf: []u8, off: u32) T {
            const n = encode.read(u32, buf[off..]);
            return T.init(buf, n + off);
        }
    }.func;
}

pub fn ReadByteVec(
    comptime T: type,
    comptime off: u32,
    comptime default: ?[]const u8,
) fn (T) []const u8 {
    return struct {
        pub fn func(t: T) []const u8 {
            const o = t._tab.offset(off);
            return if (o != 0)
                t._tab.byteVector(o + t._tab.pos)
            else if (default) |d|
                d
            else
                unreachable;
        }
    }.func;
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

// TODO rename to ReadScalar()
pub fn ReadWithDefault(
    comptime T: type,
    comptime U: type,
    comptime off: u32,
    comptime presence: Presence(U),
) fn (T) U {
    return struct {
        fn func(t: T) U {
            const o = t._tab.offset(off);
            // std.debug.print("ReadWithDefault({s}) o={}", .{ @typeName(T), o });
            return if (o != 0)
                t._tab.read(U, o + t._tab.pos)
            else if (presence == .optional)
                presence.optional.?
            else
                unreachable;
        }
    }.func;
}

pub fn Has(
    comptime T: type,
    comptime off: u32,
) fn (T) bool {
    return struct {
        fn func(t: T) bool {
            const o = t._tab.offset(off);
            return o != 0;
        }
    }.func;
}

/// retrieves the relative offset stored at `offset`.
pub fn indirect(t: Table, off: u32) u32 {
    return off + t.read(u32, off);
}

/// gets a string from data stored inside the flatbuffer.
pub fn string(t: Table, off: u32) []const u8 {
    // TODO verify utf8?
    return t.byteVector(off);
}

fn Presence(comptime T: type) type {
    return union(enum) {
        required,
        optional: ?T,
    };
}

pub fn String(
    comptime T: type,
    comptime off: u32,
    comptime presence: Presence([]const u8),
) fn (T) []const u8 {
    return struct {
        pub fn func(t: T) []const u8 {
            const o = t._tab.offset(off);
            return if (o != 0)
                t._tab.string(o + t._tab.pos)
            else if (presence == .optional)
                presence.optional.?
            else
                unreachable;
        }
    }.func;
}

/// gets a byte slice from data stored inside the flatbuffer.
pub fn byteVector(t: Table, off_: u32) []const u8 {
    const off = off_ + t.read(u32, off_);
    const start = off + size_u32;
    const length = t.read(u32, off);
    // std.log.debug("start={} length={} bytes.len={} off={}", .{ start, length, t.bytes.len, off });
    return t.bytes[start .. start + length];
}

/// retrieves the length of the vector whose offset is stored at
/// "off" in this object.
pub fn vectorLen(t: Table, off_: u32) u32 {
    var off = off_ + t.pos;
    off += t.read(u32, off);
    return t.read(u32, off);
}

pub fn VectorLen(
    comptime T: type,
    comptime off: u32,
) fn (T) u32 {
    return struct {
        pub fn func(t: T) u32 {
            return t._tab.readVectorLen(off);
        }
    }.func;
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

pub fn VectorAt(
    comptime T: type,
    comptime C: type,
    comptime off: u32,
    comptime default: ?C,
) fn (T, usize) if (default == null) ?C else C {
    return struct {
        pub fn func(t: T, j: usize) if (default == null) ?C else C {
            const o = t._tab.offset(off);
            if (o != 0) {
                if (@typeInfo(C) == .Struct and @hasDecl(C, "init")) {
                    var x = t._tab.vector(o);
                    x += @intCast(u32, j) * 4;
                    x = t._tab.indirect(x);
                    return C.init(t._tab.bytes, x);
                } else if (comptime std.meta.trait.isZigString(C)) {
                    const a = t._tab.vector(o);
                    return string(t._tab, a + @intCast(u32, j) * 4);
                } else {
                    const a = t._tab.vector(o);
                    return t._tab.read(C, a + @intCast(u32, j) * @sizeOf(C));
                }
            }
            return if (default == null) null else default.?;
        }
    }.func;
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

/// reads a T from t.bytes starting at "off". supports float, int and enum Ts
pub fn read(t: Table, comptime T: type, off: u32) T {
    return encode.read(T, t.bytes[off..]);
}

pub fn ReadStruct(
    comptime T: type,
    comptime C: type,
    comptime off: u32,
) fn (T) ?C {
    return struct {
        fn func(t: T) ?C {
            const o = t._tab.offset(off);
            if (o != 0) {
                const x = o + t._tab.pos;
                return C.init(t._tab.bytes, x);
            }
            return null;
        }
    }.func;
}

pub fn ReadStructIndirect(
    comptime T: type,
    comptime C: type,
    comptime off: u32,
) fn (T) ?C {
    return struct {
        pub fn func(t: T) ?C {
            const o = t._tab.offset(off);
            if (o != 0) {
                const x = t._tab.indirect(o + t._tab.pos);
                return C.init(t._tab.bytes, x);
            }
            return null;
        }
    }.func;
}

// pub fn ReadUnionType(
//     comptime T: type,
//     comptime C: type,
//     comptime off: u32,
// ) fn (T) C {
//     return struct {
//         fn func(t: T) ?C {
//             const o = t._tab.offset(off);
//             return if (o != 0)
//                 @intToEnum(C, t._tab.read(C, o + t._tab.pos))
//             else
//                 @intToEnum(C, 0);
//         }
//     }.func;
// }

/// writes a T at the given offset
pub fn mutate(t: Table, comptime T: type, off: u32, n: T) bool {
    encode.write(T, t.bytes[off..], n);
    return true;
}

// writes a T at given vtable location
pub fn mutateSlot(t: Table, comptime T: type, slot: u16, n: T) bool {
    const off = t.offset(slot);
    if (off != 0) {
        _ = t.mutate(T, t.pos + off, n);
        return true;
    } else return false;
}

// retrieve the T that the given vtable location
// points to. If the vtable value is zero, the default value `d`
// will be returned.
pub fn getSlot(t: Table, comptime T: type, slot: u16, d: T) T {
    const off = t.offset(slot);
    if (off == 0) return d;
    return t.read(T, t.pos + off);
}
