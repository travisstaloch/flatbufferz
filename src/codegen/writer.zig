const std = @import("std");
const StringPool = @import("string_pool.zig").StringPool;
const types = @import("types.zig");

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

fn getBaseType(ty: types.BaseType) ![]const u8 {
    return switch (ty) {
        .Bool => "bool",
        .Byte => "i8",
        .UByte => "u8",
        .Short => "i16",
        .UShort => "u16",
        .Int => "i32",
        .UInt => "u32",
        .Long => "i64",
        .ULong => "u64",
        .Float => "f32",
        .Double => "f64",
        .String => "[]const u8",
        else => |t| {
            log.err("invalid base type {any}", .{t});
            return error.InvalidBaseType;
        },
    };
}

pub const CodeWriter = struct {
    const Self = @This();
    const ImportDeclarations = std.StringHashMap([]const u8);

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

    fn writeTypeDeclaration(self: *Self, writer: anytype, obj_or_enum: anytype) !void {
        const declaration = try self.getIdentifier(getDeclarationName(obj_or_enum.DeclarationFile()));
        try self.addDeclaration(declaration);

        const typename = try self.getIdentifier(obj_or_enum.Name());
        try writer.print("{s}.{s}", .{ declaration, typename });
    }

    fn getIdentifier(self: *Self, ident: []const u8) ![]const u8 {
        const zig = std.zig;
        if (zig.Token.getKeyword(ident) != null or zig.primitives.isPrimitive(ident)) {
            const buf = try std.fmt.allocPrint(self.allocator, "@\"{s}\"", .{ident});
            defer self.allocator.free(buf);
            return self.string_pool.getOrPut(buf);
        } else {
            return ident;
        }
    }

    // This struct owns returned string.
    fn getType(self: *Self, ty: types.Type, is_object: bool) ![]const u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        var writer = buf.writer();

        switch (ty.BaseType()) {
            .Array => {
                try writer.print("[{d}]", .{ty.FixedLength()});
                // try writeBaseType(writer, ty.Element());
            },
            .Vector => {
                try writer.writeAll("std.ArrayListUnmanaged(");
                // try writeBaseType(writer, ty.Element());
                try writer.writeByte(')');
                try self.import_declarations.put("std", "std");
            },
            .Obj => {
                const index = @intCast(u32, ty.Index());
                if (self.schema.Objects(index)) |obj| {
                    try self.writeTypeDeclaration(writer, obj);
                } else {
                    log.err("object type index {d} not in schema", .{index});
                    try writer.writeAll("not_in_schema");
                }
                if (is_object) try writer.writeByte('T');
            },
            .Union => {
                const index = @intCast(u32, ty.Index());
                if (self.schema.Enums(index)) |enum_| {
                    try self.writeTypeDeclaration(writer, enum_);
                } else {
                    log.err("enum type index {d} not in schema", .{index});
                    try writer.writeAll("not_in_schema");
                }
                if (is_object) try writer.writeByte('T');
            },
            else => |t| return try getBaseType(t),
        }

        return self.string_pool.getOrPut(buf.items);
    }

    fn writeObjectFields(self: *Self, writer: anytype, object: types.Object, comptime is_object: bool) !void {
        for (0..object.FieldsLen()) |i| {
            const field = object.Fields(i).?;
            const ty = field.Type().?;
            if (field.Deprecated() or ty.BaseType() == .UType) continue;
            const name = try self.getIdentifier(field.Name());
            const typename = try self.getType(ty, is_object);
            try writeComment(writer, field, true);
            if (is_object) {
                try writer.print("\n    {s}: {s},", .{ name, typename });
            } else {
                try writer.print(
                    \\
                    \\pub fn {0s}(self: Self) {1s} {{
                    \\    return self.table.read({1s}, self.table._tab.pos);
                    \\}}
                , .{ name, typename });
            }
        }
    }

    fn writeObject2(self: *Self, writer: anytype, object: types.Object, comptime is_object: bool) !void {
        try writeComment(writer, object, true);
        try writer.writeByte('\n');
        try writer.print("pub const {s}{s} = struct {{", .{ object.Name(), if (is_object) "T" else "" });
        try self.putDeclaration("flatbufferz", "flatbufferz");
        if (!is_object) try writer.writeAll("\n       table: flatbufferz.Table,\n\n");
        try writer.writeAll("\npub const Self = @This();\n");
        try self.writeObjectFields(writer, object, is_object);
        try writer.writeAll("\n};");
    }

    pub fn writeObject(self: *Self, writer: anytype, object: types.Object) !void {
        try self.writeObject2(writer, object, false);
        if (self.opts.object_api) try self.writeObject2(writer, object, true);
    }

    fn writeEnumFields(self: *Self, writer: anytype, enum_: types.Enum, is_union: bool, comptime is_object: bool) !void {
        for (0..enum_.ValuesLen()) |i| {
            const enum_val = enum_.Values(i).?;
            try writeComment(writer, enum_val, true);
            if (is_union) {
                if (enum_val.Value() == 0) {
                    try writer.print("\n\t{s},", .{enum_val.Name()});
                } else {
                    const ty = enum_val.UnionType().?;
                    const typename = try self.getType(ty, is_object);
                    try writer.print("\n\t{s}: {s},", .{ enum_val.Name(), typename });
                }
            } else {
                try writer.print("\n\t{s} = {},", .{ enum_val.Name(), enum_val.Value() });
            }
        }
    }

    fn writeEnum2(self: *Self, writer: anytype, enum_: types.Enum, comptime is_object: bool) !void {
        const name = try self.getIdentifier(enum_.Name());
        const base_type = enum_.UnderlyingType().?.BaseType();
        const is_union = base_type == .Union or base_type == .UType;

        try writeComment(writer, enum_, true);
        try writer.print("\npub const {s}{s} = ", .{ name, if (is_object) "T" else "" });
        if (is_union) {
            try writer.writeAll("union(");
            if (is_object) {
                try writer.print("{s}.Tag", .{name});
            } else {
                try writer.writeAll("enum");
            }
            try writer.writeAll(") {");
        } else {
            const typename = try getBaseType(enum_.UnderlyingType().?.BaseType());
            try writer.print(" = enum({s}) {{", .{typename});
        }
        try self.writeEnumFields(writer, enum_, is_union, false);
        if (is_union) {
            try writer.writeAll("\n\n\tpub const Tag = std.meta.Tag(@This());");
            if (self.opts.object_api) {
                try writer.writeAll(
                    \\
                    \\
                    \\      const Self = @This();
                    \\
                    \\      pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
                    \\              switch (self.*) {
                    \\                      inline else => |*maybe_field| if (maybe_field) |field| {
                    \\                              field.deinit(allocator);
                    \\                              maybe_field = null;
                    \\                      },
                    \\              }
                    \\      }
                    \\
                    \\      pub fn Pack(self: Self, builder: *flatbufferz.Builder) !u32 {
                    \\              switch (self) {
                    \\                      inline else => |maybe_field| maybe_field.?.Pack(allocator, builder),
                    \\              }
                    \\      }
                    \\
                    \\      pub fn Unpack(self: Self, allocator: Allocator, table: flatbufferz.Table) !Self {
                    \\              return switch (self) {
                    \\                      inline else => |maybe_field, tag| brk: {
                    \\                              const Flat = @TypeOf(maybe_field.?.Tag);
                    \\                              var flat = Flat.init(table.bytes, table.pos);
                    \\                              const Object = @TypeOf(maybe_field);
                    \\                              const object = Object.Unpack(allocator, flat);
                    \\                              return @unionInit(Self, @tagName(tag),object);
                    \\                      },
                    \\              };
                    \\      }
                );
                try self.putDeclaration("std", "std");
                try self.putDeclaration("flatbufferz", "flatbufferz");
            }
        }

        try writer.writeAll("\n};");
    }

    pub fn writeEnum(self: *Self, writer: anytype, enum_: types.Enum) !void {
        try self.writeEnum2(writer, enum_, false);
        if (self.opts.object_api) try self.writeEnum2(writer, enum_, true);
    }

    pub fn writeImportDeclarations(self: Self, writer: anytype) !void {
        // Rely on index file. This can cause recursive deps for the root file, but zig handles that
        // without a problem.
        var iter = self.import_declarations.iterator();
        while (iter.next()) |kv| {
            try writer.print("const {s} = @import(\"{s}\"); ", .{ kv.key_ptr.*, kv.value_ptr.* });
        }
    }
};
