const std = @import("std");
const mem = std.mem;
fn HashFn(comptime size: u8) type {
    return *const fn ([]const u8) std.meta.Int(.unsigned, size);
}
fn NamedHashFn(comptime size: u8) type {
    return struct { []const u8, HashFn(size) };
}

fn Fnv1a16(input: []const u8) u16 {
    return @truncate(u16, std.hash.Fnv1a_32.hash(input));
}

fn Fnv1_64(input: []const u8) u64 {
    const prime: u64 = 0x00000100000001b3;
    var hash: u64 = 0xcbf29ce484222645;
    for (input) |c| {
        hash *= prime;
        hash ^= c;
    }
    return hash;
}

fn Fnv1_32(input: []const u8) u32 {
    const prime: u32 = 0x01000193;
    var hash: u32 = 0x811C9DC5;
    for (input) |c| {
        hash *= prime;
        hash ^= c;
    }
    return hash;
}
fn Fnv1_16(input: []const u8) u16 {
    return @truncate(u16, Fnv1_32(input));
}

fn hashFunctions(comptime size: u8) [2]NamedHashFn(size) {
    return .{
        .{ "fnv1_" ++ std.fmt.comptimePrint("{}", .{size}), switch (size) {
            16 => Fnv1_16,
            32 => Fnv1_32,
            64 => Fnv1_64,
            else => unreachable,
        } },
        .{
            "fnv1a_" ++ std.fmt.comptimePrint("{}", .{size}),
            switch (size) {
                16 => Fnv1a16,
                32 => std.hash.Fnv1a_32.hash,
                64 => std.hash.Fnv1a_64.hash,
                else => unreachable,
            },
        },
    };
}

pub fn findHashFunction(comptime size: u8, name: []const u8) ?HashFn(size) {
    const hfs = comptime hashFunctions(size);
    for (hfs) |hf| {
        if (mem.eql(u8, name, hf[0])) return hf[1];
    }
    return null;
}
