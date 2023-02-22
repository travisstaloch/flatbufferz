const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const assert = std.debug.assert;

pub fn posixPath(path: []u8) []u8 {
    for (path) |c, i| {
        if (c == '\\') path[i] = '/';
    }
    return path;
}

pub fn stripFileName(path: []const u8) []const u8 {
    const idx = mem.lastIndexOfScalar(u8, path, std.fs.path.sep) orelse path.len;
    return path[0..idx];
}

pub fn fileExists(path: []const u8) bool {
    std.log.debug("fileExists({s})", .{path});
    fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn hashFile(path: []const u8, contents: []const u8) u64 {
    var hash: u64 = 0;
    if (path.len > 0)
        hash = std.hash.CityHash64.hash(path);
    assert(contents.len > 0);
    hash ^= std.hash.CityHash64.hash(contents);
    return hash;
}

pub fn loadFile(allocator: mem.Allocator, filename: []const u8) ![:0]u8 {
    std.log.debug("loadFile({s})", .{filename});
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    return file.readToEndAllocOptions(allocator, std.math.maxInt(u32), null, 1, 0);
}

pub fn concatPathFileName(
    allocator: mem.Allocator,
    dir: []const u8,
    filename: []const u8,
) ![]const u8 {
    return std.fs.path.join(allocator, &.{ dir, filename });
}

pub fn relativeToRootPath(
    alloc: mem.Allocator,
    project: []const u8,
    filepath: []const u8,
) ![]const u8 {
    var absolute_project = std.ArrayList(u8).init(alloc);
    defer absolute_project.deinit();
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const project_abs = try std.fs.realpath(project, &buf);
    try absolute_project.appendSlice(posixPath(project_abs));
    if (absolute_project.getLast() != '/')
        try absolute_project.append('/');
    const filepath_abs = try std.fs.realpath(filepath, &buf);
    const absolute_filepath = posixPath(filepath_abs);

    // Find the first character where they disagree.
    // The previous directory is the lowest common ancestor;
    var common_prefix_len: usize = 0;
    var a = absolute_project.items.ptr;
    var b = absolute_filepath.ptr;
    const a_end = @ptrToInt(a + absolute_project.items.len);
    const b_end = @ptrToInt(b + absolute_filepath.len);
    while (@ptrToInt(a) < a_end and @ptrToInt(b) < b_end and a[0] == b[0]) {
        if (a[0] == '/') common_prefix_len = @ptrToInt(a) -
            @ptrToInt(absolute_project.items.ptr);
        a += 1;
        b += 1;
    }
    // the number of ../ to prepend to b depends on the number of remaining
    // directories in A.
    var suffix = absolute_project.items.ptr + common_prefix_len;
    const suffix_end = @ptrToInt(absolute_project.items.ptr +
        absolute_project.items.len);
    var num_up: usize = 0;
    while (@ptrToInt(suffix) < suffix_end) : (suffix += 1) {
        if (suffix[0] == '/') num_up += 1;
    }
    num_up -= 1; // last one is known to be '/'.
    var result = std.ArrayList(u8).init(alloc);
    try result.appendSlice("//");
    var i: usize = 0;
    while (i < num_up) : (i += 1) try result.appendSlice("../");
    try result.appendSlice(absolute_filepath[common_prefix_len + 1 ..]);
    return result.toOwnedSlice();
}

pub inline fn isAlphaChar(c: u8, comptime alpha: u8) bool {
    comptime assert(std.ascii.isAlphabetic(alpha));
    // ASCII only: alpha to upper case => reset bit 0x20 (~0x20 = 0xDF).
    return ((c & 0xDF) == (alpha & 0xDF));
}

pub inline fn findLastNotScalar(slice: []const u8, value: u8) ?usize {
    var i: usize = slice.len;
    while (i != 0) {
        i -= 1;
        if (slice[i] != value) return i;
    }
    return null;
}

pub inline fn findLastNot(slice: []const u8, values: []const u8) ?usize {
    var i: usize = slice.len;
    while (i != 0) {
        i -= 1;
        for (values) |value| {
            if (slice[i] != value) return i;
        }
    }
    return null;
}

pub fn numToString(alloc: mem.Allocator, id: anytype) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{}", .{id});
}

pub fn stringToNumber(str: []const u8, ptr: anytype) bool {
    const P = @TypeOf(ptr);
    comptime assert(std.meta.trait.is(.Pointer)(P));
    ptr.* = std.fmt.parseInt(std.meta.Child(P), str, 10) catch return false;
    return true;
}

pub fn ToUTF8(ucc: u21, out: []const u8) i32 {
    _ = ucc;
    _ = out;
    unreachable;
}

// Fast checking that character lies in closed range: [a <= x <= b]
// using one compare (conditional branch) operator.
pub fn check_ascii_range(x: u8, comptime a: u8, comptime b: u8) bool {
    comptime assert(a <= b);
    // (Hacker's Delight): `a <= x <= b` <=> `(x-a) <={u} (b-a)`.
    // The x, a, b will be promoted to int and subtracted without overflow.
    // return static_cast<unsigned int>(x - a) <= static_cast<unsigned int>(b - a);
    // TODO convert to unsigned int?
    const xx = @as(i32, x);
    const aa = @as(i32, a);
    const bb = @as(i32, b);
    const actual = @bitCast(u32, xx - aa) <= @bitCast(u32, bb - aa);
    const expected = a <= x and x <= b;
    assert(expected == actual);
    return actual;
    // return
}

pub fn ptrGreater(a: anytype, b: anytype) bool {
    return @ptrToInt(a) > @ptrToInt(b);
}
