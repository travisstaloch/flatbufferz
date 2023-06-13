const std = @import("std");
const StringPool = @import("string_pool.zig").StringPool;
const types = @import("types.zig");
const Type = @import("./type.zig").Type;

const Allocator = std.mem.Allocator;
const log = types.log;

fn writeComment(writer: anytype, e: anytype, doc_comment: bool) !void {
    const prefix = if (doc_comment) "///" else "//";
    for (0..e.DocumentationLen()) |i| if (e.Documentation(i)) |d| try writer.print("\n{s}{s}", .{ prefix, d });
}

pub fn getBasename(fname: []const u8) []const u8 {
    const last_slash = std.mem.lastIndexOf(u8, fname, "/") orelse 0;
    return fname[last_slash + 1 ..];
}

fn getDeclarationName(fname: []const u8) []const u8 {
    const basename = getBasename(fname);
    const first_dot = std.mem.indexOfScalar(u8, basename, '.') orelse basename.len;
    return basename[0..first_dot];
}

fn changeCase(writer: anytype, input: []const u8, mode: enum { camel, title }) !void {
    var capitalize_next = mode == .title;
    for (input, 0..) |c, i| {
        switch (c) {
            '_', '-', ' ' => {
                capitalize_next = true;
            },
            else => {
                try writer.writeByte(if (i == 0 and mode == .camel)
                    std.ascii.toLower(c)
                else if (capitalize_next)
                    std.ascii.toUpper(c)
                else
                    c);
                capitalize_next = false;
            },
        }
    }
}

fn toCamelCase(writer: anytype, input: []const u8) !void {
    try changeCase(writer, input, .camel);
}

test "toCamelCase" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try toCamelCase(buf.writer(), "not_camel_case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);

    try buf.resize(0);
    try toCamelCase(buf.writer(), "Not_Camel_Case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);

    try buf.resize(0);
    try toCamelCase(buf.writer(), "Not Camel Case");
    try std.testing.expectEqualStrings("notCamelCase", buf.items);
}

fn toTitleCase(writer: anytype, input: []const u8) !void {
    try changeCase(writer, input, .title);
}

fn toSnakeCase(writer: anytype, input: []const u8) !void {
    for (input, 0..) |c, i| {
        if (((c >= 'A' and c <= 'Z') or c == ' ') and i != 0) try writer.writeByte('_');
        if (c != ' ') try writer.writeByte(std.ascii.toLower(c));
    }
}

fn fieldLessThan(context: void, a: types.Field, b: types.Field) bool {
    _ = context;
    return a.Id() < b.Id();
}

pub const CodeWriter = struct {
    const Self = @This();
    const ImportDeclarations = std.StringHashMap([]const u8);
    const IndexOffset = struct {
        index: usize,
        offset: usize,
    };

    allocator: Allocator,
    import_declarations: ImportDeclarations,
    string_pool: StringPool,
    schema: types.Schema,
    opts: types.Options,

    pub fn init(allocator: Allocator, schema: types.Schema, opts: types.Options) Self {
        return .{
            .allocator = allocator,
            .import_declarations = ImportDeclarations.init(allocator),
            .string_pool = StringPool.init(allocator),
            .schema = schema,
            .opts = opts,
        };
    }

    pub fn deinit(self: *Self) void {
        self.import_declarations.deinit();
        self.string_pool.deinit();
    }

    fn putDeclaration(self: *Self, decl: []const u8, mod: []const u8) !void {
        const owned_decl = try self.string_pool.getOrPut(decl);
        const owned_mod = try self.string_pool.getOrPut(mod);
        try self.import_declarations.put(owned_decl, owned_mod);
    }

    fn addDeclaration(self: *Self, declaration: []const u8) !void {
        var module = std.ArrayList(u8).init(self.allocator);
        defer module.deinit();

        try module.appendSlice(declaration);
        try module.appendSlice("_types");
        try module.appendSlice(self.opts.extension);
        try self.putDeclaration(declaration, module.items);
    }

    // This struct owns returned string
    fn getIdentifier(self: *Self, ident: []const u8) ![]const u8 {
        const zig = std.zig;
        if (zig.Token.getKeyword(ident) != null or zig.primitives.isPrimitive(ident)) {
            const buf = try std.fmt.allocPrint(self.allocator, "@\"{s}\"", .{ident});
            defer self.allocator.free(buf);
            return self.string_pool.getOrPut(buf);
        } else {
            return self.string_pool.getOrPut(ident);
        }
    }

    // This struct owns returned string
    fn getPrefixedIdentifier(self: *Self, ident: []const u8, prefix: []const u8) ![]const u8 {
        var prefixed = std.fmt.allocPrint(self.allocator, "{s} {s}", .{ prefix, ident });
        defer self.allocator.free(prefixed);

        return try getIdentifier(prefixed);
    }

    // This struct owns returned string
    fn getFunctionName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toCamelCase(res.writer(), name);
        return try self.getIdentifier(res.items);
    }

    // This struct owns returned string
    fn getFieldName(self: *Self, name: []const u8) ![]const u8 {
        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toSnakeCase(res.writer(), name);
        return self.string_pool.getOrPut(res.items);
    }

    // This struct owns returned string
    fn getTypeName(self: *Self, name: []const u8, is_packed: bool) ![]const u8 {
        var tmp = std.ArrayList(u8).init(self.allocator);
        defer tmp.deinit();

        if (is_packed) try tmp.appendSlice("packed ");
        try tmp.appendSlice(name);

        var res = std.ArrayList(u8).init(self.allocator);
        defer res.deinit();

        try toTitleCase(res.writer(), tmp.items);
        return try self.getIdentifier(res.items);
    }

    fn getMaybeModuleTypeName(self: *Self, type_: Type) ![]const u8 {
        switch (type_.base_type) {
            .Array, .Vector => |t| {
                const next_type = Type{
                    .base_type = type_.element,
                    .index = type_.index,
                    .is_packed = type_.is_packed,
                };
                const next_name = try self.getMaybeModuleTypeName(next_type);
                if (t == .Array) {
                    return try std.fmt.allocPrint(self.allocator, "[{d}]{s}", .{ type_.fixed_len, next_name });
                } else {
                    return try std.fmt.allocPrint(self.allocator, "[]{s}", .{next_name});
                }
            },
            // Capture the modules.
            else => |t| {
                if (type_.child(self.schema)) |child| {
                    const decl_name = getDeclarationName(child.declarationFile());
                    const module = try self.getTypeName(decl_name, false);
                    try self.addDeclaration(module);

                    const typename = try self.getTypeName(child.name(), type_.is_packed);
                    if (t == .Union) log.debug("utype {any} module {s} child {s}", .{ type_, child.declarationFile(), typename });
                    return std.fmt.allocPrint(self.allocator, "{s}{s}.{s}{s}", .{ if (type_.is_optional) "?" else "", module, typename, if (t == .UType) ".Tag" else "" });
                } else if (t == .UType or t == .Obj or t == .Union) {
                    const err = try std.fmt.allocPrint(self.allocator, "type index {d} for {any} not in schema", .{ type_.index, t });
                    log.err("{s}", .{err});
                    return err;
                } else {
                    return try std.fmt.allocPrint(self.allocator, "{s}", .{type_.name()});
                }
            },
        }
    }

    // This struct owns returned string.
    fn getType(self: *Self, type_: types.Type, is_packed: bool, is_optional: bool) ![]const u8 {
        var ty = Type.init(type_);
        ty.is_packed = is_packed;
        ty.is_optional = is_optional;

        const maybe_module_type_name = try self.getMaybeModuleTypeName(ty);
        defer self.allocator.free(maybe_module_type_name);

        return self.string_pool.getOrPut(maybe_module_type_name);
    }

    // Caller owns returned slice.
    fn sortedFields(self: *Self, object: types.Object) ![]types.Field {
        var res = std.ArrayList(types.Field).init(self.allocator);
        for (0..object.FieldsLen()) |i| try res.append(object.Fields(i).?);

        std.sort.pdq(types.Field, res.items, {}, fieldLessThan);

        return res.toOwnedSlice();
    }

    fn writeObjectFields(self: *Self, writer: anytype, object: types.Object, comptime is_packed: bool) !void {
        const fields = try self.sortedFields(object);
        defer self.allocator.free(fields);

        for (fields) |field| {
            const ty = field.Type().?;
            if (field.Deprecated() or ty.BaseType() == .UType) continue;
            const name = try self.getFieldName(field.Name());
            const typename = try self.getType(ty, is_packed, field.Optional());
            try writeComment(writer, field, true);
            if (is_packed) {
                const getter_name = try self.getFunctionName(name);
                var setter_buf = std.ArrayList(u8).init(self.allocator);
                defer setter_buf.deinit();
                try setter_buf.appendSlice("set");
                try setter_buf.append(std.ascii.toUpper(getter_name[0]));
                try setter_buf.appendSlice(getter_name[1..]);
                const setter_name = setter_buf.items;

                try writer.writeByte('\n');
                switch (ty.BaseType()) {
                    .UType, .Bool, .Byte, .UByte, .Short, .UShort, .Int, .UInt, .Long, .ULong, .Float, .Double => {
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\  return self.table.read({1s}, self.table._tab.pos + {3d});
                            \\}}
                            \\pub fn {2s}(self: Self, val: {1s}) void {{
                            \\  self.table._tab.mutate({1s}, self.table._tab.pos + {3d}, val);
                            \\}}
                        , .{ getter_name, typename, setter_name, field.Offset() });
                    },
                    .String => {
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\  const offset = self.table.offset({2d});
                            \\  if (offset == 0) {{
                            \\    // Vtable shows deprecated or out of bounds.
                            \\    return "";
                            \\  }} else {{
                            \\    return self.table.byteVector(offset);
                            \\  }}
                            \\}}
                        , .{ getter_name, typename, field.Offset() });
                    },
                    .Vector => {
                        // > Vectors are stored as contiguous aligned scalar elements prefixed by a 32bit element count
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\  const len_offset = self.table.offset({2d});
                            \\  const len = if (len_offset == 0) 0 else self.table.vectorLen(len_offset);
                            \\  if (len == 0) return .{{}};
                            \\  const offset = self.table.vector(len_offset);
                            \\  return std.mem.bytesAsSlice({1s}, self.table.bytes[offset..@sizeOf({1s}) * len]);
                            \\}}
                        , .{ getter_name, typename, field.Offset() });
                        try self.putDeclaration("std", "std");
                    },
                    .Obj => {
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\  const offset = self.table.offset({2d});
                            \\  if (offset == 0) {{
                            \\    // Vtable shows deprecated or out of bounds.
                            \\    return null;
                            \\  }} else {{
                            \\    const offset2 = self.table.indirect(offset);
                            \\    return {1s}.init(self.table.bytes[offset2]);
                            \\  }}
                            \\}}
                        , .{ getter_name, typename, field.Offset() });
                    },
                    .Union => {
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\  const offset = self.table.offset({2d});
                            \\  if (offset == 0) {{
                            \\    // Vtable shows deprecated or out of bounds.
                            \\    return null;
                            \\  }} else {{
                            \\    const union_table = self.table.union_(offset);
                            \\    return {1s}.init(union_table.bytes);
                            \\  }}
                            \\}}
                        , .{ getter_name, typename, field.Offset() });
                    },
                    .Array => {
                        try writer.print(
                            \\
                            \\pub fn {0s}(self: Self) {1s} {{
                            \\  // what to do for array at offset {2d}?
                            \\}}
                        , .{ getter_name, typename, field.Offset() });
                    },
                    else => {},
                }
            } else {
                try writer.print("\n    {s}: {s},", .{ name, typename });
            }
        }
    }

    // Struct owns returned string.
    fn getDefault(self: *Self, field: types.Field) ![]const u8 {
        const res = switch (field.Type().?.BaseType()) {
            .UType => try std.fmt.allocPrint(self.allocator, "@intToEnum({s}, {d})", .{ try self.getType(field.Type().?, false, false), field.DefaultInteger() }),
            .Bool, .Byte, .UByte, .Short, .UShort, .Int, .UInt, .Long, .ULong => try std.fmt.allocPrint(self.allocator, "{d}", .{field.DefaultInteger()}),
            .Float, .Double => try std.fmt.allocPrint(self.allocator, "{}", .{field.DefaultReal()}),
            .String => try std.fmt.allocPrint(self.allocator, "\"\"", .{}),
            .Vector, .Array => try std.fmt.allocPrint(self.allocator, "{s}", .{".{}"}),
            .Obj => try std.fmt.allocPrint(self.allocator, "{s}", .{if (field.Optional()) "null" else ".{}"}),
            else => |t| {
                log.err("cannot get default for base type {any}", .{t});
                return error.InvalidBaseType;
            },
        };
        defer self.allocator.free(res);

        return self.string_pool.getOrPut(res);
    }

    fn writePackForField(self: *Self, writer: anytype, field: types.Field, is_struct: bool) !void {
        if (field.Padding() != 0) try writer.print("\n    builder.pad({d});", .{field.Padding()});
        const field_name = try self.getFieldName(field.Name());
        const ty = Type.initFromField(field);
        switch (ty.base_type) {
            .None => {},
            .UType, .Bool, .Byte, .UByte, .Short, .UShort, .Int, .UInt, .Long, .ULong, .Float, .Double, .Array => {
                if (ty.is_optional or is_struct) {
                    try writer.print(
                        \\
                        \\    try builder.prepend({s}, self.{s});
                    , .{ try self.getMaybeModuleTypeName(ty), field_name });
                } else {
                    try writer.print(
                        \\
                        \\    try builder.prependSlot({s}, {d}, self.{s}, {s});
                    , .{ try self.getMaybeModuleTypeName(ty), field.Id(), field_name, try self.getDefault(field) });
                }
            },
            .String => {
                try writer.print(
                    \\
                    \\    try builder.prependSlotUOff({d}, try builder.createString(self.{s}), 0);
                , .{ field.Id(), field_name });
            },
            .Vector => {
                // > Nesting vectors is not supported, instead you can wrap the inner vector in a table.
                // - https://flatbuffers.dev/flatbuffers_guide_writing_schema.html
                const alignment = 1;
                try writer.print(
                    \\
                    \\    try builder.startVector({0d}, self.{1s}.len, {2d});
                    \\    for (self.{1s}) |ele| {{
                , .{ ty.element_size, field_name, alignment });
                const child_type = ty.child(self.schema).?.type_();
                if (child_type.isScalar()) {
                    try writer.print(
                        \\
                        \\    try builder.prepend({s}, ele);
                    , .{field_name});
                } else if (child_type.base_type == .String) {
                    try writer.print(
                        \\
                        \\    try builder.prependSlotUOff({d}, try builder.createString(ele), 0);
                    , .{field.Id()});
                } else {
                    try writer.print(
                        \\
                        \\    try builder.prependSlotUOff({d}, try ele.pack(builder), 0);
                    , .{field.Id()});
                }
                try writer.print(
                    \\
                    \\    }}
                    \\    try builder.endVector(self.{s}.len);
                , .{field_name});
            },
            .Obj, .Union => {
                try writer.print(
                    \\
                    \\    try builder.prependSlotUOff({d}, try self.{s}.pack(builder));
                , .{ field.Id(), field_name });
            },
        }
    }

    fn writePackFn(self: *Self, writer: anytype, object: types.Object) !void {
        try writer.writeAll(
            \\
            \\
            \\pub fn pack(self: Self, builder: *flatbufferz.Builder) !u32 {
        );
        try self.putDeclaration("flatbufferz", "flatbufferz");
        const fields = try self.sortedFields(object);
        defer self.allocator.free(fields);
        if (object.IsStruct()) {
            try writer.print(
                \\
                \\    try builder.prep({d}, {d});
            , .{ object.Minalign(), object.Bytesize() });
        } else {
            try writer.print(
                \\
                \\    try builder.startObject({d});
            , .{fields.len});
        }
        for (fields) |field| try self.writePackForField(writer, field, object.IsStruct());
        if (object.IsStruct()) {
            try writer.writeAll(
                \\
                \\    return builder.offset();
                \\}
            );
        } else {
            try writer.writeAll(
                \\
                \\    return builder.endObject();
                \\}
            );
        }
    }

    fn writeObject2(self: *Self, writer: anytype, object: types.Object, comptime is_packed: bool) !void {
        try writeComment(writer, object, true);
        const name = try self.getTypeName(object.Name(), false);
        const packed_name = try self.getTypeName(object.Name(), true);

        if (is_packed) {
            try writer.print("\n\npub const {s} = struct {{", .{packed_name});
            try writer.writeAll(
                \\
                \\table: flatbufferz.Table,
                \\
                \\pub const Self = @This();
                \\
                \\pub fn init(bytes: []u8) !Self {
                \\    return .{ .table = .{ ._tab = .{ .bytes = bytes, .pos = 0 } } };
                \\}
            );
            try self.putDeclaration("flatbufferz", "flatbufferz");
            try self.writeObjectFields(writer, object, is_packed);
        } else {
            try writer.print("\n\npub const {s} = struct {{", .{name});
            try self.writeObjectFields(writer, object, is_packed);
            try writer.print(
                \\
                \\
                \\pub const Self = @This();
                \\
                \\pub fn init(packed_struct: {0s}) !Self {{
                \\    var res = Self{{}};
                \\    inline for (@typeInfo(Self).Struct.fields) |f| {{
                \\        const getter = @field({0s}, f.name);
                \\        @field(res, f.name) = getter(packed_struct);
                \\    }}
                \\    return res;
                \\}}
            , .{packed_name});
            try self.writePackFn(writer, object);

            try self.putDeclaration("flatbufferz", "flatbufferz");
        }
        try self.putDeclaration("flatbufferz", "flatbufferz");
        try writer.writeAll("\n};");
    }

    pub fn writeObject(self: *Self, writer: anytype, object: types.Object) !void {
        try self.writeObject2(writer, object, false);
        try self.writeObject2(writer, object, true);
    }

    fn writeEnumFields(self: *Self, writer: anytype, enum_: types.Enum, is_union: bool, comptime is_packed: bool) !void {
        for (0..enum_.ValuesLen()) |i| {
            const enum_val = enum_.Values(i).?;
            try writeComment(writer, enum_val, true);
            if (is_union) {
                if (enum_val.Value() == 0) {
                    try writer.print("\n\t{s},", .{enum_val.Name()});
                } else {
                    const ty = enum_val.UnionType().?;
                    const typename = try self.getType(ty, is_packed, false);
                    try writer.print("\n\t{s}: {s},", .{ enum_val.Name(), typename });
                }
            } else {
                try writer.print("\n\t{s} = {},", .{ enum_val.Name(), enum_val.Value() });
            }
        }
    }

    fn writeEnum2(self: *Self, writer: anytype, enum_: types.Enum, comptime is_packed: bool) !void {
        const name = try self.getTypeName(enum_.Name(), is_packed);
        const base_type = enum_.UnderlyingType().?.BaseType();
        const is_union = base_type == .Union or base_type == .UType;

        try writer.writeByte('\n');
        try writeComment(writer, enum_, true);
        try writer.print("\n\npub const {s} = ", .{name});
        if (is_union) {
            try writer.writeAll("union(");
            if (is_packed) {
                try writer.writeAll("enum");
            } else {
                try writer.print("{s}.Tag", .{name});
            }
            try writer.writeAll(") {");
        } else {
            const typename = try self.getType(enum_.UnderlyingType().?, false, false);
            try writer.print(" enum({s}) {{", .{typename});
        }
        try self.writeEnumFields(writer, enum_, is_union, false);
        if (is_union) {
            if (is_packed) {
                try writer.writeAll("\n\npub const Tag = std.meta.Tag(@This());");
            } else {
                try writer.writeAll(
                    \\
                    \\
                    \\const Self = @This();
                    \\
                    \\pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
                    \\       switch (self.*) {
                    \\              inline else => |*maybe_field| if (maybe_field) |field| {
                    \\                     field.deinit(allocator);
                    \\                     maybe_field = null;
                    \\              },
                    \\       }
                    \\}
                    \\
                    \\pub fn Pack(self: Self, builder: *flatbufferz.Builder) !u32 {
                    \\       switch (self) {
                    \\              inline else => |maybe_field| maybe_field.?.Pack(builder),
                    \\       }
                    \\}
                    \\
                    \\pub fn Unpack(self: Self, allocator: std.mem.Allocator, table: flatbufferz.Table) !Self {
                    \\       switch (self) {
                    \\              inline else => |maybe_field, tag| {
                    \\                     const Flat = @TypeOf(maybe_field.?.Tag);
                    \\                     var flat = Flat.init(table.bytes, table.pos);
                    \\                     const Object = @TypeOf(maybe_field);
                    \\                     const object = Object.Unpack(allocator, flat);
                    \\                     return @unionInit(Self, @tagName(tag),object);
                    \\              },
                    \\       }
                    \\}
                );
                try self.putDeclaration("std", "std");
                try self.putDeclaration("flatbufferz", "flatbufferz");
            }
        }

        try writer.writeAll("\n};");
    }

    pub fn writeEnum(self: *Self, writer: anytype, enum_: types.Enum) !void {
        try self.writeEnum2(writer, enum_, false);
        try self.writeEnum2(writer, enum_, true);
    }

    fn isRootTable(self: Self, name: []const u8) bool {
        return if (self.schema.RootTable()) |root_table|
            std.mem.eql(u8, name, root_table.Name())
        else
            false;
    }

    pub fn writePrelude(self: *Self, writer: anytype, prelude: types.Prelude, name: []const u8) !void {
        try writer.print(
            \\//!
            \\//! generated by flatc-zig
            \\//! binary:     {s}
            \\//! schema:     {s}.fbs
            \\//! file ident: {?s}
            \\//! typename    {?s}
            \\//!
            \\
        , .{ prelude.bfbs_path, prelude.filename_noext, prelude.file_ident, name });
        try self.writeImportDeclarations(writer);

        if (self.isRootTable(name)) {
            try writer.print(
                \\
                \\
                \\pub const file_ident: flatbufferz.Builder.Fid = "{s}".*;
                \\pub const file_ext = "{s}";
            , .{ self.schema.FileIdent(), self.schema.FileExt() });
        }
    }

    fn writeImportDeclarations(self: Self, writer: anytype) !void {
        // Rely on index file. This can cause recursive deps for the root file, but zig handles that
        // without a problem.
        try writer.writeByte('\n');
        var iter = self.import_declarations.iterator();
        while (iter.next()) |kv| {
            try writer.print("\nconst {s} = @import(\"{s}\"); ", .{ kv.key_ptr.*, kv.value_ptr.* });
        }
    }
};
