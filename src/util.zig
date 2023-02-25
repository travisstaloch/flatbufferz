const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const assert = std.debug.assert;
const fb = @import("flatbuffers");
const todo = fb.common.todo;

pub const Case = enum(u4) {
    Unknown = 0,
    // TheQuickBrownFox
    UpperCamel = 1,
    // theQuickBrownFox
    LowerCamel = 2,
    // the_quick_brown_fox
    Snake = 3,
    // THE_QUICK_BROWN_FOX
    ScreamingSnake = 4,
    // THEQUICKBROWNFOX
    AllUpper = 5,
    // thequickbrownfox
    AllLower = 6,
    // the-quick-brown-fox
    Dasher = 7,
    // THEQuiCKBr_ownFox (or whatever you want, we won't change it)
    Keep = 8,
    // the_quick_brown_fox123 (as opposed to the_quick_brown_fox_123)
    Snake2 = 9,
};

pub fn posixPath(path: []u8) []u8 {
    for (path, 0..) |c, i| {
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

// Save data "buf" into file "name" returning true if
// successful, false otherwise.  If "binary" is false
// data is written using ifstream's text mode, otherwise
// data is written with no transcoding.
pub fn saveFile(path: []const u8, buf: []const u8, binary: bool) !void {
    _ = binary;
    // return SaveFile(name, buf.c_str(), buf.size(), binary);
    // std::ofstream ofs(name, binary ? std::ofstream::binary : std::ofstream::out);
    // if (!ofs.is_open()) return false;
    // ofs.write(buf, len);
    // return !ofs.bad();
    const file = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
    defer file.close();
    try file.writeAll(buf);
}

const isLower = std.ascii.isLower;
const isDigit = std.ascii.isDigit;
const toLower = std.ascii.toLower;

pub fn camelToSnake(input: []const u8, writer: anytype) !void {
    for (input, 0..) |c, i| {
        if (i == 0) {
            try writer.writeByte(toLower(c));
        } else if (c == '_') {
            try writer.writeByte('_');
        } else if (!isLower(c)) {
            // Prevent duplicate underscores for Upper_Snake_Case strings
            // and UPPERCASE strings.
            if (isLower(input[i - 1]) or (isDigit(input[i - 1]) and !isDigit(c))) {
                try writer.writeByte('_');
            }
            try writer.writeByte(toLower(c));
        } else {
            try writer.writeByte(c);
        }
    }
}
pub fn dasherToSnake(input: []const u8) []const u8 {
    _ = input;
    todo("dasherToSnake", .{});
}

pub fn toCamelCase(input: []const u8, first: bool) []const u8 {
    _ = input;
    _ = first;
    todo("toCamelCase", .{});
    // std::string s;
    // for (size_t i = 0; i < input.length(); i++) {
    //   if (!i && first)
    //     s += CharToUpper(input[i]);
    //   else if (input[i] == '_' && i + 1 < input.length())
    //     s += CharToUpper(input[++i]);
    //   else
    //     s += input[i];
    // }
    // return s;
}

pub fn toSnakeCase(input: []const u8, screaming: bool) []const u8 {
    _ = input;
    _ = screaming;
    todo("toSnakeCase", .{});
    // std::string s;
    // for (size_t i = 0; i < input.length(); i++) {
    //   if (i == 0) {
    //     s += screaming ? CharToUpper(input[i]) : CharToLower(input[i]);
    //   } else if (input[i] == '_') {
    //     s += '_';
    //   } else if (!islower(input[i])) {
    //     // Prevent duplicate underscores for Upper_Snake_Case strings
    //     // and UPPERCASE strings.
    //     if (islower(input[i - 1]) || (isdigit(input[i-1]) && !isdigit(input[i]))) { s += '_'; }
    //     s += screaming ? CharToUpper(input[i]) : CharToLower(input[i]);
    //   } else {
    //     s += screaming ? CharToUpper(input[i]) : input[i];
    //   }
    // }
    // return s;
}

pub fn toAll(input: []const u8, comptime transform: fn (u8) u8) []const u8 {
    _ = input;
    _ = transform;
    todo("toAll", .{});

    // std::string ToAll(const std::string &input,
    //                          std::function<char(const char)> transform) {
    //   std::string s;
    //   for (size_t i = 0; i < input.length(); i++) { s += transform(input[i]); }
    //   return s;
}

pub fn toDasher(input: []const u8) []const u8 {
    _ = input;
    todo("toDasher", .{});

    // std::string ToDasher(const std::string &input) {
    //   std::string s;
    //   char p = 0;
    //   for (size_t i = 0; i < input.length(); i++) {
    //     char const &c = input[i];
    //     if (c == '_') {
    //       if (i > 0 && p != kPathSeparator &&
    //           // The following is a special case to ignore digits after a _. This is
    //           // because ThisExample3 would be converted to this_example_3 in the
    //           // CamelToSnake conversion, and then dasher would do this-example-3,
    //           // but it expects this-example3.
    //           !(i + 1 < input.length() && isdigit(input[i + 1])))
    //         s += "-";
    //     } else {
    //       s += c;
    //     }
    //     p = c;
    //   }
    //   return s;
}

// Converts foo_bar_123baz_456 to foo_bar123_baz456
pub fn snakeToSnake2(input: []const u8) []const u8 {
    _ = input;
    todo("snakeToSnake2", .{});

    // std::string SnakeToSnake2(const std::string &s) {
    //   if (s.length() <= 1) return s;
    //   std::string result;
    //   result.reserve(s.size());
    //   for (size_t i = 0; i < s.length() - 1; i++) {
    //     if (s[i] == '_' && isdigit(s[i + 1])) {
    //       continue;  // Move the `_` until after the digits.
    //     }

    //     result.push_back(s[i]);

    //     if (isdigit(s[i]) && isalpha(s[i + 1]) && islower(s[i + 1])) {
    //       result.push_back('_');
    //     }
    //   }
    //   result.push_back(s.back());

    //   return result;
}

pub const CaseTransform = packed struct {
    input: Case,
    output: Case,

    pub fn init(output: Case, input: Case) CaseTransform {
        return .{
            .input = input,
            .output = output,
        };
    }
    pub fn asInt(tx: CaseTransform) u8 {
        return @bitCast(u8, tx);
    }
    pub fn int(input: Case, output: Case) u8 {
        return CaseTransform.init(input, output).asInt();
    }
};

pub fn convertCase(
    input: []const u8,
    // tx_fn: void,
    case_tx: CaseTransform,
    writer: anytype,
) !void {
    // _ = input;
    // _ = tx_fn;
    // if (case_tx.output == .Keep) return input;
    switch (case_tx.asInt()) {
        CaseTransform.int(.Snake, .LowerCamel) => return camelToSnake(input, writer),
        else => todo("CaseTransform {}", .{case_tx}),
    }
    todo("input={s} in={s} out={s} ", .{ input, @tagName(case_tx.input), @tagName(case_tx.output) });
    // // The output cases expect snake_case inputs, so if we don't have that input
    // // format, try to convert to snake_case.
    // switch (input_case) {
    //     .LowerCamel,
    //     .UpperCamel,
    //     => return convertCase( try camelToSnake(input, writer), output_case, .Snake, writer),
    //     .Dasher => return convertCase( dasherToSnake(input), output_case, .Snake, writer),
    //     .Keep => common.panicf("WARNING: Converting from Keep case.\n", .{}),
    //     else => {},
    // }

    // return switch (output_case) {
    //     .UpperCamel => toCamelCase(input, true),
    //     .LowerCamel => toCamelCase(input, false),
    //     .Snake => input,
    //     .ScreamingSnake => toSnakeCase(input, true),
    //     .AllUpper => toAll(input, std.ascii.toUpper),
    //     .AllLower => toAll(input, std.ascii.toUpper),
    //     .Dasher => toDasher(input),
    //     .Snake2 => snakeToSnake2(input),
    //     else => input,
    // };
}
