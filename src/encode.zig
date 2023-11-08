const std = @import("std");
const mem = std.mem;
const Builder = @import("Builder.zig");
const size_prefix_length = Builder.size_prefix_length;

pub const vtable_metadata_fields = 2;

pub const FlatBuffer = struct {
    buf: []const u8,
    i: u32,

    pub fn init(buf: []const u8, i: u32) FlatBuffer {
        return .{ .buf = buf, .i = i };
    }
};

/// GetRootAs is a generic helper to initialize a FlatBuffer with the provided
/// buffer bytes and its data offset.
pub fn getRootAs(buf: []u8, offset: u32) !FlatBuffer {
    const n = try mem.readInt(u32, buf[offset..], .little);
    return FlatBuffer.init(buf, n + offset);
}

/// GetSizePrefixedRootAs is a generic helper to initialize a FlatBuffer with
/// the provided size-prefixed buffer
/// bytes and its data offset
pub fn getSizePrefixedRootAs(buf: []u8, offset: u32) !FlatBuffer {
    const n = try mem.readInt(u32, buf[offset + size_prefix_length ..], .little);
    return FlatBuffer.init(buf, n + offset + size_prefix_length);
}

/// GetSizePrefix reads the size from a size-prefixed flatbuffer
pub fn getSizePrefix(buf: []u8, offset: u32) u32 {
    return mem.readInt(u32, buf[offset..], .little);
}

/// GetIndirectOffset retrives the relative offset in the provided buffer stored
///  at `offset`.
pub fn getIndirectOffset(buf: []u8, offset: u32) u32 {
    return offset + mem.readInt(u32, buf[offset..], .little);
}

/// read a little-endian T from buf.
pub fn read(comptime T: type, buf: []const u8) T {
    const info = @typeInfo(T);
    switch (info) {
        .Float => {
            const I = @Type(.{ .Int = .{
                .signedness = .unsigned,
                .bits = info.Float.bits,
            } });
            return @bitCast(mem.readInt(I, buf[0..@sizeOf(T)], .little));
        },
        .Bool => return buf[0] != 0,
        .Enum => {
            const Tag = info.Enum.tag_type;
            const taginfo = @typeInfo(Tag);
            const I = @Type(.{
                .Int = .{
                    .signedness = taginfo.Int.signedness,
                    // ceilPowerOfTwo(@max()) is needed here for union(enum)
                    // Tags which may have odd tag sizes
                    .bits = comptime std.math.ceilPowerOfTwo(u16, @max(taginfo.Int.bits, 8)) catch
                        unreachable,
                },
            });
            const i = mem.readInt(I, buf[0..@sizeOf(I)], .little);
            return std.meta.intToEnum(T, i) catch
                std.debug.panic(
                "invalid enum value '{}' for '{s}' with Tag '{s}' and I '{s}'",
                .{ i, @typeName(T), @typeName(Tag), @typeName(I) },
            );
        },
        else => return mem.readInt(T, buf[0..@sizeOf(T)], .little),
    }
}

/// write a little-endian T from a byte slice.
pub fn write(comptime T: type, buf: []u8, t: T) void {
    const info = @typeInfo(T);
    switch (info) {
        .Float => {
            const I = @Type(.{ .Int = .{
                .signedness = .unsigned,
                .bits = info.Float.bits,
            } });
            mem.writeInt(I, buf[0..@sizeOf(T)], @as(I, @bitCast(t)), .little);
        },
        .Bool => mem.writeInt(u8, buf[0..1], @intFromBool(t), .little),
        .Enum => {
            const Tag = info.Enum.tag_type;
            const taginfo = @typeInfo(Tag);
            const I = @Type(.{
                .Int = .{
                    .signedness = taginfo.Int.signedness,
                    .bits = comptime std.math.ceilPowerOfTwo(u16, @max(8, taginfo.Int.bits)) catch
                        unreachable,
                },
            });
            mem.writeInt(I, buf[0..@sizeOf(I)], @intFromEnum(t), .little);
        },
        else => mem.writeInt(T, buf[0..@sizeOf(T)], t, .little),
    }
}
