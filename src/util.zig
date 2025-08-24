const std = @import("std");
const mem = std.mem;

pub fn expectExtension(extension: []const u8, path: []const u8) !void {
    if (!hasExtension(extension, path)) {
        std.log.err(
            "expected '{s}' extension. got '{s}' in path '{s}'",
            .{ extension, std.fs.path.extension(path), path },
        );
        return error.UnexpectedFileExtension;
    }
}

pub fn hasExtension(extension: []const u8, path: []const u8) bool {
    return mem.eql(u8, std.fs.path.extension(path), extension);
}

pub fn toCamelCase(input: []const u8, first: bool, writer: *std.Io.Writer) !void {
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        _ = try writer.writeByte(if (i == 0 and first)
            std.ascii.toUpper(c)
        else if (c == '_' and i + 1 < input.len)
            std.ascii.toUpper(blk: {
                i += 1;
                break :blk input[i];
            })
        else
            c);
    }
}

/// get a field in declaration order rather than alphabetic order
pub fn getFieldIdxById(o: anytype, id: u32) ?u32 {
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        if (field.Id() == id) return i;
    }
    return null;
}
