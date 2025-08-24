const std = @import("std");
const fb = @import("flatbufferz");
const reflection = fb.reflection;

// TODO field default values - need to check presence. ie Monster.friendly is a
// bool defaulting to false.  as is, we can't detect it.
pub fn bfbsToFbs(alloc: std.mem.Allocator, filename: []const u8, writer: *std.io.Writer) !void {
    const f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();
    const buf = try f.readToEndAlloc(alloc, std.math.maxInt(u16));
    defer alloc.free(buf);

    const schema = reflection.Schema.GetRootAs(buf, 0);
    if (schema.RootTable()) |root_table|
        try writer.print("// root_table={s}\n", .{root_table.Name()});

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
            const field = o.Fields(fb.util.getFieldIdxById(o, @intCast(j)).?).?;
            try writeDocumentation(field, writer);
            try writer.print("  {s}: {s}", .{ field.Name(), @tagName(field.Type().?.BaseType()) });
            if (field.DefaultInteger() != 0)
                try writer.print(" = {}", .{field.DefaultInteger()});

            try writeAttributes(field, writer, .{ .write_parens = true });
            try writer.print("; // offset={}", .{field.Offset()});
            if (field.Optional()) _ = try writer.write(" optional");
            if (field.Required()) _ = try writer.write(" required");
            _ = try writer.write("\n");
        }
        try writer.print("}}\n", .{});
    }
}

fn writeDocumentation(e: anytype, writer: *std.Io.Writer) !void {
    for (0..e.DocumentationLen()) |i| {
        if (e.Documentation(i)) |d| try writer.print("//{s}\n", .{d});
    }
}

fn writeAttributes(
    e: anytype,
    writer: *std.Io.Writer,
    opts: struct { write_parens: bool = false },
) !void {
    const len = e.AttributesLen();
    if (len > 0 and opts.write_parens) _ = try writer.write(" (");
    for (0..len) |i| {
        if (i != 0) _ = try writer.write(", ");
        if (e.Attributes(i)) |a| {
            _ = try writer.write(a.Key());
            if (a.Value().len != 0) try writer.print(": \"{s}\"", .{a.Value()});
        }
    }
    if (len > 0 and opts.write_parens) _ = try writer.write(") ");
}
