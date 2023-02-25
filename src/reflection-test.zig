const std = @import("std");
const testing = std.testing;
const talloc = testing.allocator;
const reflection = @import("reflection.zig");

test "monster_test.bfbs" {
    const stderr = std.io.getStdErr().writer();
    try bfbsToFbs(talloc, "samples/monster_test.bfbs", stderr);
}

fn writeDocumentation(e: anytype, writer: anytype) !void {
    for (0..e.DocumentationLen()) |i| {
        if (e.Documentation(i)) |d| try writer.print("//{s}\n", .{d});
    }
}

fn writeAttributes(
    e: anytype,
    writer: anytype,
    opts: struct { write_parens: bool = false },
) !void {
    const len = e.AttributesLen();
    if (len > 0 and opts.write_parens) _ = try writer.write(" (");
    for (0..len) |i| {
        if (i != 0) _ = try writer.write(", ");
        if (e.Attributes(i)) |a| {
            _ = try writer.write(a.Key());
            if (a.Value()) |v| try writer.print(": \"{s}\"", .{v});
        }
    }
    if (len > 0 and opts.write_parens) _ = try writer.write(") ");
}

// TODO field default values - need to check presence. ie Monster.friendly is a
// bool defaulting to false.  as is, we can't detect it.
pub fn bfbsToFbs(alloc: std.mem.Allocator, filename: []const u8, writer: anytype) !void {
    const f = try std.fs.cwd().openFile(filename, .{});
    const buf = try f.readToEndAlloc(talloc, std.math.maxInt(u16));
    defer alloc.free(buf);

    const schema = reflection.Schema.GetRootAs(buf, 0);
    try writer.print("// root_object={s}\n", .{schema.RootObject().?.Name()});

    for (0..schema.EnumsLen()) |i| {
        const e = schema.Enums(i).?;
        const tyname = if (e.IsUnion()) "union" else "enum";
        try writeDocumentation(e, writer);
        try writer.print("{s} {s}", .{ tyname, e.Name() });
        try writeAttributes(e, writer, .{ .write_parens = true });
        try writer.print(" {{ // utype={s}\n", .{@tagName(e.UnderlyingType().?.BaseType())});
        for (0..e.ValuesLen()) |j| {
            const v = e.Values(j).?;
            try writeDocumentation(v, writer);
            try writer.print("  {s}={},\n", .{ v.Name(), v.Value() });
        }
        try writer.print("}}\n", .{});
    }

    for (0..schema.ObjectsLen()) |i| {
        const o = schema.Objects(i).?;
        const tyname = if (o.IsStruct()) "struct" else "table";

        try writeDocumentation(o, writer);
        try writer.print("{s} {s} ", .{ tyname, o.Name() });
        try writeAttributes(o, writer, .{ .write_parens = true });
        try writer.print("{{ // bytesize={} \n", .{o.Bytesize()});
        for (0..o.FieldsLen()) |j| {
            const field = o.Fields(j).?;
            try writeDocumentation(field, writer);
            try writer.print("  {s}: {s}", .{ field.Name(), @tagName(field.Type().?.BaseType()) });
            const int = field.DefaultInteger();
            if (int != 0) try writer.print(" = {}", .{int});

            _ = try writer.write(" (");
            try writeAttributes(field, writer, .{});
            try writer.print("); //  {s}{s} {}\n", .{
                if (field.Optional()) "optional" else "",
                if (field.Required()) "required" else "",
                field.Offset(),
            });
        }
        try writer.print("}}\n", .{});
    }
}
