//!
//! this is a port of https://github.com/google/flatbuffers/blob/master/src/idl_gen_go.cpp
//!

const std = @import("std");
const mem = std.mem;
const fb = @import("flatbufferz");
const refl = fb.reflection;
const Schema = refl.Schema;
const Enum = refl.Enum;
const EnumVal = refl.EnumVal;
const Object = refl.Object;
const Field = refl.Field;
const Type = refl.Type;
const BaseType = fb.idl.BaseType;
const util = fb.util;
const common = fb.common;
const todo = common.todo;

fn genComment(e: anytype, writer: anytype) !void {
    for (0..e.DocumentationLen()) |i| {
        if (e.Documentation(i)) |d| try writer.print("//{s}\n", .{d});
    }
}

fn zigScalarTypename(base_type: BaseType) []const u8 {
    return switch (base_type) {
        .BOOL => "bool",
        .CHAR => "i8",
        .UCHAR => "u8",
        .SHORT => "i16",
        .USHORT => "u16",
        .INT => "i32",
        .UINT => "u32",
        .LONG => "i64",
        .ULONG => "u64",
        .FLOAT => "f32",
        .DOUBLE => "f64",
        .STRING => "[]const u8",
        .VECTOR, .STRUCT, .UNION, .ARRAY, .UTYPE, .NONE => unreachable,
    };
}

pub const scalar_sizes = blk: {
    const tags = std.meta.tags(BaseType);
    var result = [1]u32{~@as(u32, 0)} ** tags.len;
    inline for (tags, 0..) |tag, i| {
        result[i] = if (tag == .BOOL)
            1
        else if (tag == .STRING)
            16
        else if (tag.isScalar()) scalar: {
            const zigtypename = if (tag != .UTYPE)
                zigScalarTypename(tag)
            else
                continue;
            break :scalar if (std.mem.endsWith(u8, zigtypename, "64"))
                8
            else if (std.mem.endsWith(u8, zigtypename, "32"))
                4
            else if (std.mem.endsWith(u8, zigtypename, "16"))
                2
            else if (std.mem.endsWith(u8, zigtypename, "8"))
                1
            else
                @compileLog(tag);
        } else continue;
    }
    break :blk result;
};

fn lastName(namespaced_name: []const u8) []const u8 {
    const last_dot = if (std.mem.lastIndexOfScalar(u8, namespaced_name, '.')) |i| i + 1 else 0;
    return namespaced_name[last_dot..];
}

/// write a type name to writer.
/// mode:
///   .keep_namespace: fully qualified
///   .skip_namespace: only write the last name component
fn genTypeBasic(
    ty: Type,
    schema: Schema,
    mode: enum { skip_namespace, keep_namespace },
    writer: anytype,
) !void {
    const base_ty = ty.BaseType();
    if (base_ty.isScalar() and ty.Index() != -1 or base_ty == .UNION) {
        const e = schema.Enums(@intCast(u32, ty.Index())).?;
        const name = switch (mode) {
            .keep_namespace => e.Name(),
            .skip_namespace => lastName(e.Name()),
        };
        _ = try writer.write(name);
    } else if (base_ty.isScalar() or base_ty == .STRING)
        _ = try writer.write(zigScalarTypename(base_ty))
    else if (base_ty.isStruct()) {
        const o = schema.Objects(@intCast(u32, ty.Index())).?;
        const name = switch (mode) {
            .keep_namespace => o.Name(),
            .skip_namespace => lastName(o.Name()),
        };
        _ = try writer.write(name);
    } else if (base_ty == .NONE) {
        _ = try writer.write("void");
    } else if (base_ty == .VECTOR) {
        const ele = ty.Element();
        if (ele.isScalar() or ele == .STRING)
            _ = try writer.write(zigScalarTypename(ele))
        else if (ele.isStruct()) {
            const o = schema.Objects(@intCast(u32, ty.Index())).?;
            const name = switch (mode) {
                .keep_namespace => o.Name(),
                .skip_namespace => lastName(o.Name()),
            };
            _ = try writer.write(name);
        } else todo("genTypeBasic() base_ty={} ele={}", .{ base_ty, ele });
    } else todo("genTypeBasic() base_ty={}", .{base_ty});
}

/// Create a type for the enum values.
fn genEnumType(e: Enum, writer: anytype, schema: Schema) !void {
    _ = try writer.write("pub const ");
    try genTypeBasic(e.UnderlyingType().?, schema, .skip_namespace, writer);
    _ = try writer.write(" = enum {\n");
}

/// A single enum member.
fn enumMember(_: Enum, ev: EnumVal, writer: anytype) !void {
    try writer.print("  {s} = {},\n", .{ ev.Name(), ev.Value() });
}

fn genEnum(e: Enum, schema: Schema, writer: anytype) !void {
    // Generate enum declarations.
    // TODO check if already generated

    try genComment(e, writer);
    try genEnumType(e, writer, schema);
    {
        var i: u32 = 0;
        while (i < e.ValuesLen()) : (i += 1) {
            const ev = e.Values(i).?;
            try genComment(ev, writer);
            try enumMember(e, ev, writer);
        }
    }
    try writer.print(
        \\pub fn tagName(v: {s}) []const u8 {{
        \\  return @tagName(v);
        \\}}
        \\}};
        \\
        \\
    , .{e.Name()});
}

/// gen a union(E) decl
fn genNativeUnion(e: Enum, schema: Schema, writer: anytype) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print("pub const {s}T = union({s}) {{\n", .{ last_name, last_name });
    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        _ = try writer.write(ev.Name());
        _ = try writer.write(": ");
        try genTypeBasic(ev.UnionType().?, schema, .keep_namespace, writer);
        _ = try writer.write(",\n");
    }
}

/// gen a union pack() method
fn genNativeUnionPack(e: Enum, writer: anytype) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print(
        \\
        \\pub fn pack(rcv: {s}T, b: *Builder) !void {{
        \\  switch (t) {{
        \\
    ,
        .{last_name},
    );

    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        if (ev.Value() == 0)
            try writer.print("    .{s} => {{}},\n", .{ev.Name()})
        else
            try writer.print("    .{s} => |x| try x.pack(b),\n", .{ev.Name()});
    }
    _ = try writer.write(
        \\  }
        \\}
        \\
        \\
    );
}

/// gen a union unpack() method
fn genNativeUnionUnpack(e: Enum, schema: Schema, writer: anytype) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print(
        "pub fn unpack(rcv: {s}, table: Table) {s}T {{\n",
        .{ last_name, last_name },
    );
    _ = try writer.write("  switch (t) {\n");
    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        if (ev.Value() == 0)
            try writer.print(".{s} => return .{s},\n", .{ ev.Name(), ev.Name() })
        else {
            try writer.print(".{s} => {{\n", .{ev.Name()});

            _ = try writer.write("var x = ");
            try genTypeBasic(ev.UnionType().?, schema, .skip_namespace, writer);
            try writer.print(
                \\.init(table.bytes, table.pos);
                \\return .{{ .{s} = x.unpack() }};
                \\}},
                \\
            , .{ev.Name()});
        }
    }
    _ = try writer.write(
        \\  }
        \\  unreachable;
        \\}
        \\
        \\
    );
}

/// Save out the generated code to a .fb.zig file
fn saveType(
    gen_path: []const u8,
    typename: []const u8,
    contents: []const u8,
    needs_imports: bool,
    kind: enum { enum_, struct_ },
) !void {
    if (contents.len == 0) return;

    _ = .{ needs_imports, kind };
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    _ = try writer.write(gen_path);
    try writer.writeByte(std.fs.path.sep);
    for (typename) |c| {
        try writer.writeByte(if (c == '.') '/' else c);
    }
    _ = try writer.write(".fb.zig");
    const outpath = fbs.getWritten();
    std.fs.cwd().makePath(std.fs.path.dirname(outpath).?) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("couldn't make dir {?s}", .{std.fs.path.dirname(outpath)});
            return e;
        },
    };
    const f = try std.fs.cwd().createFile(outpath, .{});
    defer f.close();
    _ = try f.write(contents);
}

fn genPrelude(
    bfbs_path: []const u8,
    file_ident: []const u8,
    basename: []const u8,
    writer: anytype,
) !void {
    try writer.print(
        \\//!
        \\//! generated by flatc-zig
        \\//! binary:     {s}
        \\//! schema:     {s}.fbs
        \\//! file ident: {?s}
        \\//!
        \\
        \\const fb = @import("flatbufferz");
        \\const Builder = fb.Builder;
        \\
    , .{ bfbs_path, basename, file_ident });
}

fn hasAttribute(x: anytype, key: []const u8) bool {
    var i: u32 = 0;
    while (i < x.AttributesLen()) : (i += 1) {
        const a = x.Attributes(i).?;
        if (mem.eql(u8, a.Key(), key)) return true;
    }
    return false;
}

fn isStruct(object_index: i32, schema: Schema) bool {
    const o = schema.Objects(@bitCast(u32, object_index)).?;
    return o.IsStruct();
}

fn genNativeTablePack(o: Object, schema: Schema, writer: anytype) !void {
    const oname = o.Name();
    const struct_type = lastName(oname);
    try writer.print("pub fn pack(rcv: {s}T, b: *Builder) u32 {{\n", .{struct_type});
    {
        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(i).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            if (field_base_ty.isScalar()) continue;
            const fname = field.Name();
            if (field_base_ty == .STRING) {
                try writer.print(
                    \\const {0s}_off = if (rcv.{0s}.items.len != 0) try b.createString(rcv.{0s}) else 0;
                    \\
                , .{fname});
            } else if (field_base_ty.isVector() and
                field_ty.Element() == .UCHAR and
                !field_base_ty.isUnion())
            {
                try writer.print(
                    \\const {0s}_off = if (rcv.{0s}.items.len != 0) try b.createByteString(rcv.{0s}) else 0;
                    \\
                , .{fname});
            } else if (field_base_ty.isVector()) {
                try writer.print(
                    \\var {0s}_off: u32 = 0;
                    \\if (rcv.{0s}.items.len != 0) {{
                    \\const {0s}_len = rcv.{0s}.items.len;
                    \\
                , .{fname});
                const fty_ele = field_ty.Element();
                if (fty_ele == .STRING) {
                    try writer.print(
                        \\var {0s}_offsets = make([]u32, {0s}_len);
                        \\for ({0s}_offsets) |*off, j| {{
                        \\off.* = try b.createString(rcv.{0s}[j]);
                        \\}}
                        \\
                    , .{fname});
                } else if (fty_ele == .STRUCT and isStruct(field_ty.Index(), schema)) {
                    try writer.print(
                        \\var {0s}_offsets = make([]u32, {0s}_len);
                        \\for ({0s}_offsets) |*off, j| {{
                        \\off.* = try rcv.{0s}[j].pack(b);
                        \\}}
                        \\
                    , .{fname});
                }

                const fname_camel_upper = util.fmtCamelUpper(fname);
                try writer.print(
                    \\try {s}.Start{}Vector(b, {2s}_off);
                    \\{{
                    \\var j = {2s}_len - 1;
                    \\while (true) : (j -= 1) {{
                    \\
                , .{ struct_type, fname_camel_upper, fname });
                if (fty_ele.isScalar()) {
                    try writer.print(
                        "try b.prepend({s}, rcv.{s}[j]);\n",
                        .{ zigScalarTypename(fty_ele), fname },
                    );
                } else if (fty_ele == .STRUCT and isStruct(field_ty.Index(), schema)) {
                    try writer.print("try rcv.{s}[j].pack(b)\n", .{fname});
                } else {
                    try writer.print("try b.prependUOff({s}_offsets[j]);\n", .{fname});
                }
                try writer.print(
                    \\if (j == 0) break;
                    \\}}
                    \\{0s}_off = b.endVector({0s}_len);
                    \\}}
                    \\}}
                    \\
                , .{fname});
            } else if (field_base_ty == .STRUCT) {
                if (isStruct(field_ty.Index(), schema)) continue;
                try writer.print(
                    "const {0s}_off = try rcv.{0s}.pack(b);\n",
                    .{fname},
                );
            } else if (field_base_ty == .UNION) {
                try writer.print(
                    "const {0s}_off = try rcv.{0s}.pack(b);\n",
                    .{fname},
                );
            } else unreachable;
        }
    }

    try writer.print("{s}.Start(b);\n", .{struct_type});

    {
        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(i).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            const fname = field.Name();
            const fname_camel_upper = util.fmtCamelUpper(fname);
            if (field_base_ty.isScalar()) {
                const is_optional = hasAttribute(field, "optional");
                if (is_optional) todo("optional", .{});
                if (field_base_ty != .UNION)
                    try writer.print(
                        "try {s}.Add{s}(b, rcv.{s});\n",
                        .{ struct_type, fname_camel_upper, fname },
                    );

                if (is_optional) todo("optional", .{});
            } else {
                if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema)) {
                    try writer.print(
                        "{0s}_off = try rcv.{0s}.pack(b);\n",
                        .{fname},
                    );
                } else if (field_base_ty == .UNION) {
                    try writer.print(
                        "try {s}.Add{s}T(b, rcv.{s});\n",
                        .{ struct_type, fname_camel_upper, fname },
                    );
                }
                try writer.print(
                    "{s}.Add{s}(b, {s}_off);\n",
                    .{ struct_type, fname_camel_upper, fname },
                );
            }
        }
    }
    try writer.print("return {s}.End(b);\n}}\n\n", .{struct_type});
}

fn genNativeTableUnpack(o: Object, schema: Schema, writer: anytype) !void {
    const oname = o.Name();
    const struct_type = lastName(oname);
    try writer.print("pub fn unpackTo(rcv: {s}, t: *{s}T) void {{\n", .{ struct_type, struct_type });
    {
        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(i).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            const fname = field.Name();
            const fname_upper_camel = util.fmtCamelUpper(fname);
            if (field_base_ty.isScalar() or field_base_ty == .STRING) {
                if (field_base_ty.isUnion()) continue;
                try writer.print("t.{s} = rcv.{s}();\n", .{ fname, fname_upper_camel });
            } else if (field_base_ty == .VECTOR and
                field_ty.Element() == .UCHAR and
                field_ty.Index() == -1)
            {
                try writer.print("t.{s} = rcv.{s}Bytes();\n", .{ fname, fname_upper_camel });
            } else if (field_base_ty == .VECTOR) {
                try writer.print(
                    \\const {0s}_len = rcv.{1s}Len();
                    \\t.{0s} = try std.ArrayListUnmanaged(
                , .{ fname, fname_upper_camel });
                try genTypeBasic(field_ty, schema, .keep_namespace, writer);
                try writer.print(
                    \\).initCapacity({0s}_len);
                    \\var j: u32 = 0;
                    \\while (j < {0s}_len) : (j += 1) {{
                , .{fname});
                if (field_ty.Element() == .STRUCT) {
                    _ = try writer.write("var x: ");
                    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
                    try writer.print(" = undefined;\nrcv.{s}(&x, j);\n", .{fname_upper_camel});
                }
                try writer.print("t.{s}.appendAssumeCapacity(", .{fname});
                if (field_ty.Element().isScalar()) {
                    try writer.print("rcv.{s}(j)", .{fname_upper_camel});
                } else if (field_ty.Element() == .STRING) {
                    try writer.print("rcv.{s}(j)", .{fname_upper_camel});
                } else if (field_ty.Element() == .STRUCT) {
                    _ = try writer.write("x.unpack()");
                } else {
                    // TODO(iceboy): Support vector of unions.
                    unreachable;
                }
                _ = try writer.write(
                    \\);
                    \\}
                    \\
                );
            } else if (field_base_ty == .STRUCT) {
                try writer.print("t.{s} = rcv.{s}.unpack();\n", .{ fname, fname });
            } else if (field_base_ty == .UNION) {
                try writer.print(
                    \\var {0s}_table = Table{{}};
                    \\if (rcv.{1s}(&{0s}_table)) {{
                    \\t.{0s} = rcv.{0s}().unpack({0s}_table); // FIXME can't be right
                    \\}}
                    \\
                , .{ fname, fname_upper_camel });
            } else unreachable;
        }
    }

    _ = try writer.write("}\n\n");
    try writer.print(
        \\pub fn  unpack(rcv: {s}) {s}T {{
        \\var t = {s}T{{}};
        \\rcv.unpackTo(&t);
        \\return t;
        \\}}
        \\
        \\
    , .{ struct_type, struct_type, struct_type });
}

fn genNativeStructPack(o: Object, schema: Schema, writer: anytype) !void {
    const olastname = lastName(o.Name());
    try writer.print(
        \\pub fn pack(rcv: {0s}, b: *Builder) !void {{
        \\return {0s}.Create(b
    , .{olastname});

    var nameprefix = NamePrefix{};
    try structPackArgs(o, &nameprefix, schema, writer);
    _ = try writer.write(
        \\);
        \\}
        \\
    );
}

fn structPackArgs(o: Object, nameprefix: *NamePrefix, schema: Schema, writer: anytype) !void {
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        const field_ty = field.Type().?;
        if (field_ty.BaseType() == .STRUCT) {
            const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
            try nameprefix.appendSlice(field.Name());
            try nameprefix.append('_');
            try structPackArgs(o2, nameprefix, schema, writer);
        } else try writer.print(", rcv.{s}{s}", .{ nameprefix.constSlice(), field.Name() });
    }
}

fn genNativeStructUnpack(o: Object, writer: anytype) !void {
    const olastname = lastName(o.Name());
    try writer.print(
        \\pub fn unpackTo(rcv: {0s}, t: *{0s}T) !void {{
    , .{olastname});
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        const field_ty = field.Type().?;
        const fname = field.Name();
        const fname_camel_upper = util.fmtCamelUpper(fname);
        if (field_ty.BaseType() == .STRUCT)
            try writer.print(
                "t.{s} = try rcv.{s}(null).unpack();\n",
                .{ fname, fname_camel_upper },
            )
        else
            try writer.print(
                "t.{s} = try rcv.{s}();\n",
                .{ fname, fname_camel_upper },
            );
    }

    try writer.print(
        \\}}
        \\
        \\pub fn unpack(rcv: {0s}) !{0s}T {{
        \\var t = {0s}T{{}};
        \\try rcv.unpackTo(&t);
        \\return t;
        \\}}
        \\
        \\
    , .{olastname});
}

fn genNativeStruct(o: Object, schema: Schema, writer: anytype) !void {
    const oname = o.Name();
    const last_name = lastName(oname);

    try writer.print("pub const {s}T = struct {{\n", .{last_name});
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        if (field.Deprecated()) continue;
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        if (field_base_ty.isScalar() and field_base_ty == .UNION) continue;
        _ = try writer.write(field.Name());
        _ = try writer.write(": ");
        if (field_base_ty.isVector()) {
            _ = try writer.write("std.ArrayListUnmanaged(");
            try genTypeBasic(field_ty, schema, .keep_namespace, writer);
            _ = try writer.write(")");
        } else try genTypeBasic(field_ty, schema, .keep_namespace, writer);
        _ = try writer.write(",\n");
    }
    _ = try writer.write("\n");
    if (!o.IsStruct()) {
        try genNativeTablePack(o, schema, writer);
        try genNativeTableUnpack(o, schema, writer);
    } else {
        try genNativeStructPack(o, schema, writer);
        try genNativeStructUnpack(o, writer);
    }
    _ = try writer.write("};\n\n");
}

/// Begin a struct decl
fn beginStruct(o: Object, writer: anytype) !void {
    const oname = o.Name();
    const last_name = lastName(oname);
    try writer.print(
        \\pub const {s} = struct {{
        \\_tab: {s},
        \\
        \\
    , .{ last_name, if (o.IsStruct()) "fb.Struct" else "fb.Table" });
}

fn newRootTypeFromBuffer(o: Object, writer: anytype) !void {
    try writer.print(
        \\pub fn GetRootAs(buf: []const u8, offset: u32) {0s} {{
        \\const n = fb.read(u32, buf[offset..]);
        \\return {0s}.Init(buf, n+offset);
        \\}}
        \\
        \\
    , .{lastName(o.Name())});
}

fn initializeExisting(o: Object, writer: anytype) !void {
    // Initialize an existing object with other data, to avoid an allocation.
    try writer.print(
        \\pub fn init(bytes: []const u8, pos: u32) {s} {{
        \\return .{{ ._tab = .{{ .bytes = bytes, .pos = pos }}}};
        \\}}
        \\
        \\
    , .{lastName(o.Name())});
}

fn genTableAccessor(o: Object, writer: anytype) !void {
    // Initialize an existing object with other data, to avoid an allocation.
    try writer.print(
        \\pub fn Table(x: {s}) fb.Table {{
        \\return x._tab;
        \\}}
        \\
        \\
    , .{lastName(o.Name())});
}

/// Get the length of a vector.
fn getVectorLen(o: Object, field: Field, writer: anytype) !void {
    const fname = field.Name();
    const fname_camel_upper = util.fmtCamelUpper(fname);
    try writer.print(
        \\pub fn {s}Len(rcv: {s}) u32 
    , .{ fname_camel_upper, o.Name() });
    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\return rcv._tab.vectorLen(o);
        \\}
        \\return 0;
        \\}
        \\
        \\
    );
}

/// Get a [ubyte] vector as a byte slice.
fn getUByteSlice(o: Object, field: Field, writer: anytype) !void {
    const fname = field.Name();
    const fname_camel_upper = util.fmtCamelUpper(fname);
    try writer.print(
        \\pub fn {s}Bytes(rcv: {s}) []const u8
    , .{ fname_camel_upper, o.Name() });
    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\return rcv._tab.byteVector(o + rcv._tab.pos);
        \\}
        \\return "";
        \\}
        \\
        \\
    );
}

/// writes the function name that is able to read a value of the given type.
fn genGetter(ty: Type, schema: Schema, writer: anytype) !void {
    switch (ty.BaseType()) {
        .STRING => _ = try writer.write("rcv._tab.byteVector("),
        .UNION => _ = try writer.write("rcv._tab.union_"),
        .VECTOR => switch (ty.Element()) {
            .STRING => _ = try writer.write("rcv._tab.byteVector("),
            .UNION => _ = try writer.write("rcv._tab.union_("),
            .VECTOR => todo(".VECTOR .VECTOR", .{}),
            else => |ele| {
                _ = try writer.write("try rcv._tab.read(");
                if (ele.isScalar() or ele == .STRING) {
                    _ = try writer.write(zigScalarTypename(ele));
                    _ = try writer.write(", ");
                } else todo("genGetter .VECTOR {}", .{ele});
            },
        },
        else => {
            _ = try writer.write("try rcv._tab.read(");
            try genTypeBasic(ty, schema, .skip_namespace, writer);
            _ = try writer.write(", ");
        },
    }
}

/// Most field accessors need to retrieve and test the field offset first,
/// this is the prefix code for that.
fn offsetPrefix(field: Field, writer: anytype) !void {
    try writer.print(
        \\{{
        \\const o = rcv._tab.offset({});
        \\if (o != 0) {{
        \\
    , .{field.Offset()});
}

fn isScalarOptional(field: Field, field_base_ty: BaseType) bool {
    return field_base_ty.isScalar() and field.Optional();
}

fn genConstant(field: Field, field_base_ty: BaseType, schema: Schema, writer: anytype) !void {
    if (isScalarOptional(field, field_base_ty)) {
        _ = try writer.write("null");
        return;
    }
    switch (field_base_ty) {
        .BOOL => {
            const default = if (field.HasDefaultInteger())
                field.DefaultInteger() != 0
            else
                false;
            try writer.print("{}", .{default});
        },
        .FLOAT, .DOUBLE => {
            // if (StringIsFlatbufferNan(field.value.constant)) {
            //   needs_math_import_ = true;
            //   return float_type + "(math.NaN())";
            // } else if (StringIsFlatbufferPositiveInfinity(field.value.constant)) {
            //   needs_math_import_ = true;
            //   return float_type + "(math.Inf(1))";
            // } else if (StringIsFlatbufferNegativeInfinity(field.value.constant)) {
            //   needs_math_import_ = true;
            //   return float_type + "(math.Inf(-1))";
            // }
            // return field.value.constant;
            // todo("genConstant() .FLOAT", .{});
            try writer.print("{}", .{field.DefaultReal()});
        },

        else => {
            const field_ty = field.Type().?;
            if (field_ty.Index() == -1)
                try writer.print("{}", .{field.DefaultInteger()})
            else {
                _ = try writer.write("@intToEnum(");
                try genTypeBasic(field_ty, schema, .keep_namespace, writer);
                try writer.print(", {})", .{field.DefaultInteger()});
            }
        },
    }
}

/// Begin the creator function signature.
fn beginBuilderArgs(o: Object, writer: anytype) !void {
    try writer.print(
        \\pub fn Create{s}(b: *Builder
    , .{lastName(o.Name())});
}

const NamePrefix = std.BoundedArray(u8, std.fs.MAX_NAME_BYTES);

/// Recursively generate arguments for a constructor, to deal with nested
/// structs.
fn structBuilderArgs(o: Object, nameprefix: *NamePrefix, schema: Schema, writer: anytype) !void {
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema)) {
            // Generate arguments for a struct inside a struct. To ensure names
            // don't clash, and to make it obvious these arguments are constructing
            // a nested struct, prefix the name with the field name.
            const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
            try nameprefix.appendSlice(field.Name());
            try nameprefix.append('_');
            try structBuilderArgs(o2, nameprefix, schema, writer);
        } else {
            const fname = field.Name();
            try writer.print(
                \\, {s}{s}: {s}
            , .{ nameprefix.constSlice(), fname, zigScalarTypename(field_base_ty) });
        }
    }
}

/// End the creator function signature.
fn endBuilderArgs(writer: anytype) !void {
    _ = try writer.write(") u32 {\n");
}

/// Writes the method name for use with add/put calls.
fn genMethod(field: Field, schema: Schema, writer: anytype) !void {
    const field_ty = field.Type().?;
    if (field_ty.BaseType().isScalar()) {
        _ = try writer.write("(");
        try genTypeBasic(field_ty, schema, .skip_namespace, writer);
        _ = try writer.write(", ");
    } else _ = try writer.write(if (field_ty.BaseType() == .STRUCT and
        isStruct(field_ty.Index(), schema))
        "Struct("
    else
        "UOff(");
}

/// Recursively generate struct construction statements and instert manual
/// padding.
fn structBuilderBody(o: Object, nameprefix: *NamePrefix, schema: Schema, writer: anytype) !void {
    try writer.print(
        \\try b.prep({}, {});
        \\
    , .{ o.Minalign(), o.Bytesize() });
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        const padding = field.Padding();
        if (padding != 0)
            try writer.print(
                \\try b.pad({});
                \\
            , .{padding});
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema)) {
            const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
            try nameprefix.appendSlice(field.Name());
            try nameprefix.append('_');
            try structBuilderBody(o2, nameprefix, schema, writer);
        } else {
            _ = try writer.write("try b.prepend");
            try genMethod(field, schema, writer);
            try writer.print(
                \\ {s}{s});
                \\
            , .{ nameprefix.constSlice(), field.Name() });
        }
    }
}

fn endBuilderBody(writer: anytype) !void {
    _ = try writer.write(
        \\return b.offset();
        \\}
        \\
    );
}

/// Create a struct with a builder and the struct's arguments.
fn genStructBuilder(o: Object, schema: Schema, writer: anytype) !void {
    try beginBuilderArgs(o, writer);
    var nameprefix = NamePrefix{};
    try structBuilderArgs(o, &nameprefix, schema, writer);
    try endBuilderArgs(writer);
    nameprefix.len = 0;
    try structBuilderBody(o, &nameprefix, schema, writer);
    try endBuilderBody(writer);
}

// Get the value of a table's starting offset.
fn getStartOfTable(o: Object, writer: anytype) !void {
    try writer.print(
        \\pub fn Start(b: *Builder) !void {{
        \\try b.startObject({});
        \\}}
        \\
    , .{o.FieldsLen()});
}

/// Generate table constructors, conditioned on its members' types.
fn genTableBuilders(o: Object, schema: Schema, writer: anytype) !void {
    try getStartOfTable(o, writer);

    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        if (field.Deprecated()) continue;

        // const offset = it - o.fields.vec.begin();
        // FIXME: is field.Offset() correct here?
        try buildFieldOfTable(o, field, schema, field.Offset(), writer);
        if (field.Type().?.BaseType() == .VECTOR)
            try buildVectorOfTable(o, field, schema, writer);
    }

    try getEndOffsetOnTable(o, writer);
}

/// Get the value of a struct's scalar.
fn getScalarFieldOfStruct(o: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);
    try writer.print(
        \\pub fn {s}(rcv: {s}) 
    , .{ fname_camel_upper, lastName(o.Name()) });
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    _ = try writer.write("{\nreturn ");
    try genGetter(field_ty, schema, writer);
    try writer.print(
        \\rcv._tab.pos + {});
        \\}}
        \\
    , .{field.Offset()});
}

/// Get the value of a struct's scalar.
fn getScalarFieldOfTable(_: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);
    try writer.print(
        \\pub fn {s}(rcv:  
    , .{fname_camel_upper});
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    _ = try writer.write(") ");
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    try offsetPrefix(field, writer);
    const field_base_ty = field_ty.BaseType();
    if (isScalarOptional(field, field_base_ty)) {
        _ = try writer.write("const v = ");
    } else {
        _ = try writer.write("return ");
    }
    try genGetter(field_ty, schema, writer);
    try writer.print(
        \\o + rcv._tab.pos);
        \\
    , .{});
    if (isScalarOptional(field, field_base_ty)) _ = try writer.write("\nreturn v;");
    _ = try writer.write(
        \\}
        \\return 
    );
    try genConstant(field, field_base_ty, schema, writer);
    _ = try writer.write(
        \\;
        \\}
        \\
        \\
    );
}

fn getStringField(o: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);
    const oname = o.Name();
    try writer.print(
        \\pub fn {s}(rcv: {s}) 
    , .{ fname_camel_upper, lastName(oname) });
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\return 
    );
    try genGetter(field_ty, schema, writer);
    _ = try writer.write(
        \\o + rcv._tab.pos);
        \\}
        \\return "";
        \\}
        \\
        \\
    );
}

/// Get a struct by initializing an existing struct.
/// Specific to Struct.
fn getStructFieldOfStruct(o: Object, field: Field, writer: anytype) !void {
    const fname = field.Name();
    const fname_camel_upper = util.fmtCamelUpper(fname);
    const oname = o.Name();
    try writer.print(
        \\pub fn {s}(rcv: {s}, obj: *{s}) *{s} {{
        \\obj.init(rcv._tab.bytes, rcv._tab.pos + {});
        \\}}
        \\
        \\
    , .{ oname, fname_camel_upper, oname, oname, field.Offset() });
}

/// Get a struct by initializing an existing struct.
/// Specific to Table.
fn getStructFieldOfTable(_: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);

    // Get the value of a union from an object.
    try writer.print(
        \\pub fn {s}(rcv: 
    , .{fname_camel_upper});
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    _ = try writer.write(", obj: *");
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    _ = try writer.write(") ?*");
    try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    _ = try writer.write(" ");
    try offsetPrefix(field, writer);
    const field_base_ty = field_ty.BaseType();
    if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema))
        _ = try writer.write("const x = o + rcv._tab.pos;\n")
    else
        _ = try writer.write("const x = rcv._tab.indirect(o + rcv._tab.pos);\n");

    _ = try writer.write(
        \\obj.init(rcv._tab.bytes, x);
        \\return obj;
        \\}
        \\return null;
        \\}
        \\
        \\
    );
}

fn genTypePointer(ty: Type, writer: anytype) !void {
    switch (ty.BaseType()) {
        .STRING => _ = try writer.write("[]u8"),
        .VECTOR => todo("genTypePointer VECTOR", .{}),
        .STRUCT => todo("genTypePointer STRUCT", .{}),
        else => _ = try writer.write("*fb.Table"),
    }
}

fn getUnionField(o: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);
    const oname = o.Name();

    // Get the value of a union from an object.
    try writer.print(
        \\pub fn {s}(obj: 
    , .{fname_camel_upper});
    try genTypePointer(field_ty, writer);
    try writer.print(
        \\{s}) bool 
    , .{lastName(oname)});
    try offsetPrefix(field, writer);
    try genGetter(field_ty, schema, writer);
    _ = try writer.write(
        \\obj, o);
        \\return true;
        \\}
        \\return false;
        \\}
        \\
        \\
    );
}

fn inlineSize(ty: Type, schema: Schema) u32 {
    // return if(isStruct(type, schema))
    // type.struct_def->bytesize
    // : (IsArray(type)
    //        ? InlineSize(type.VectorType()) * type.fixed_length
    //        : SizeOf(type.base_type));
    // return switch(ty.BaseType()) {
    //  .NONE => todo("inlineSize NONE"),
    //  .ARRAY => todo("inlineSize ARRAY"),
    //  .VECTOR => todo("inlineSize VECTOR"),
    // };
    _ = schema;
    return ty.BaseSize();
}

/// Get the value of a vector's struct member.
fn getMemberOfVectorOfStruct(o: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);
    const oname = o.Name();
    const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
    try writer.print(
        \\pub fn {s}(rcv: {s}, obj: *{s}, j: u32) bool 
    , .{ fname_camel_upper, oname, o2.Name() });
    try offsetPrefix(field, writer);
    try writer.print(
        \\  var x = rcv._tab.vector(o);
        \\  x += j * {};
        \\  x = rcv._tab.indirect(x);
        \\  obj.init(rcv._tab.bytes, x);
        \\  return true;
        \\}}
        \\return false;
        \\}}
        \\
        \\
    , .{inlineSize(field_ty, schema)});
}

/// Get the value of a vector's non-struct member.
fn getMemberOfVectorOfNonStruct(o: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);
    const oname = o.Name();

    try writer.print(
        \\pub fn {s}(rcv: {s}, j: u32) {s} 
    , .{ fname_camel_upper, oname, zigScalarTypename(field_ty.Element()) });

    _ = try writer.write(" ");

    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\  const a = rcv._tab.vector(o);
        \\
    );

    try genGetter(field_ty, schema, writer);
    try writer.print(
        \\a + j * {});
        \\}}
        \\
    , .{inlineSize(field_ty, schema)});
    const ele_basety = field_ty.Element();
    _ = try writer.write(if (ele_basety == .STRING)
        \\return "";
        \\
    else if (ele_basety == .BOOL)
        \\return false;
        \\
    else
        \\return 0;
        \\
    );
    _ = try writer.write("}\n\n");
}

/// Set the value of a table's field.
fn buildFieldOfTable(o: Object, field: Field, schema: Schema, offset: u16, writer: anytype) !void {
    const fname = field.Name();
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(fname);

    try writer.print(
        \\pub fn Add{s}(b: *Builder, {s}: 
    , .{ fname_camel_upper, fname });

    const field_base_ty = field_ty.BaseType();
    if (!field_base_ty.isScalar() and !o.IsStruct()) {
        _ = try writer.write("u32");
    } else {
        try genTypeBasic(field_ty, schema, .keep_namespace, writer);
    }

    _ = try writer.write(
        \\) !void {
        \\try b.prepend
    );
    if (isScalarOptional(field, field_base_ty)) {
        _ = try writer.write("(");
    } else {
        _ = try writer.write("Slot");
        try genMethod(field, schema, writer);
        try writer.print("{}, ", .{offset});
    }

    _ = try writer.write(fname);

    if (isScalarOptional(field, field_base_ty)) {
        try writer.print(
            \\)
            \\b.slot({}
        , .{offset});
    } else {
        _ = try writer.write(", ");
        try genConstant(field, field_base_ty, schema, writer);
    }
    _ = try writer.write(
        \\);
        \\}
        \\
    );
}

/// Set the value of one of the members of a table's vector.
fn buildVectorOfTable(_: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname = field.Name();
    const fname_camel_upper = util.fmtCamelUpper(fname);
    const field_ty = field.Type().?;
    const ele = field_ty.Element();
    const alignment = if (ele.isScalar() or ele == .STRING)
        field_ty.ElementSize()
    else switch (ele) {
        .STRUCT => blk: {
            const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
            const minalign = o2.Minalign();
            break :blk if (minalign == -1)
                todo("alignment .STRUCT minalign == -1 ", .{})
            else
                @bitCast(u32, minalign);
        },
        .NONE,
        .VECTOR,
        .UNION,
        .ARRAY,
        => todo("alignment {}", .{ele}),
        else => unreachable,
    };
    try writer.print(
        \\pub fn Start{s}Vector(b: *Builder, num_elems: u32) !u32 {{
        \\return b.startVector({}, num_elems, {});
        \\}}
        \\
    , .{ fname_camel_upper, field_ty.ElementSize(), alignment });
}

/// Get the offset of the end of a table.
fn getEndOffsetOnTable(_: Object, writer: anytype) !void {
    try writer.print(
        \\pub fn End(b: *Builder) !u32 {{
        \\return b.endObject();
        \\}}
        \\
        \\
    , .{});
}

/// Generate a struct field getter, conditioned on its child type(s).
fn genStructAccessor(o: Object, field: Field, schema: Schema, writer: anytype) !void {
    try genComment(field, writer);
    const field_ty = field.Type().?;
    const field_base_ty = field_ty.BaseType();

    if (field_base_ty.isScalar()) {
        if (o.IsStruct())
            try getScalarFieldOfStruct(o, field, schema, writer)
        else
            try getScalarFieldOfTable(o, field, schema, writer);
    } else {
        switch (field_base_ty) {
            .STRUCT => if (o.IsStruct())
                try getStructFieldOfStruct(o, field, writer)
            else
                try getStructFieldOfTable(o, field, schema, writer),
            .STRING => try getStringField(o, field, schema, writer),
            .VECTOR => {
                if (field_ty.Element() == .STRUCT) {
                    try getMemberOfVectorOfStruct(o, field, schema, writer);
                    // TODO(michaeltle): Support querying fixed struct by key.
                    // Currently, we only support keyed tables.
                    const struct_def = schema.Objects(@bitCast(u32, field_ty.Index())).?;
                    if (!struct_def.IsStruct() and field.Key()) {
                        // try getMemberOfVectorOfStructByKey(o, field, writer);
                        todo("getMemberOfVectorOfStructByKey", .{});
                    }
                } else {
                    try getMemberOfVectorOfNonStruct(o, field, schema, writer);
                }
            },
            .UNION => try getUnionField(o, field, schema, writer),
            else => unreachable,
        }
    }
    if (field_base_ty.isVector()) {
        try getVectorLen(o, field, writer);
        if (field_ty.Element() == .UCHAR)
            try getUByteSlice(o, field, writer);
    }
}

/// Generate struct or table methods.
fn genStruct(o: Object, schema: Schema, writer: anytype, gen_obj_based_api: bool) !void {
    // TODO if (o.generated) return;

    try genComment(o, writer);
    if (gen_obj_based_api) {
        try genNativeStruct(o, schema, writer);
    }
    try beginStruct(o, writer);

    if (!o.IsStruct()) {
        // Generate a special accessor for the table that has been declared as
        // the root type.
        try newRootTypeFromBuffer(o, writer);
    }
    // Generate the Init method that sets the field in a pre-existing
    // accessor object. This is to allow object reuse.
    try initializeExisting(o, writer);
    // Generate _tab accessor
    try genTableAccessor(o, writer);

    // Generate struct fields accessors
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        if (field.Deprecated()) continue;

        try genStructAccessor(o, field, schema, writer);
        // try genStructMutator(o, field, writer);
        // todo("genStructMutator", .{});
        // TODO(michaeltle): Support querying fixed struct by key. Currently,
        // we only support keyed tables.
        if (!o.IsStruct() and field.Key()) {
            try genKeyCompare(o, field, writer);
            try genLookupByKey(o, field, writer);
        }
    }

    // Generate builders
    if (o.IsStruct()) {
        // create a struct constructor function
        try genStructBuilder(o, schema, writer);
    } else {
        // Create a set of functions that allow table construction.
        try genTableBuilders(o, schema, writer);
    }
    _ = try writer.write(
        \\};
        \\
        \\
    );
}

fn genKeyCompare(o: Object, field: Field, writer: anytype) !void {
    const fname = field.Name();
    const fname_camel_upper = util.fmtCamelUpper(fname);
    try writer.print(
        \\pub fn {s}KeyCompare(rcv: {s}) u32 {{
        \\_ = rcv;
        \\// TODO
        \\}}
    , .{ fname_camel_upper, o.Name() });
}

fn genLookupByKey(o: Object, field: Field, writer: anytype) !void {
    const fname = field.Name();
    const fname_camel_upper = util.fmtCamelUpper(fname);
    try writer.print(
        \\pub fn {s}LookupByKey(rcv: {s}) u32 {{
        \\_ = rcv;
        \\// TODO
        \\}}
    , .{ fname_camel_upper, o.Name() });
}

pub fn generate(
    alloc: mem.Allocator,
    bfbs_path: []const u8,
    gen_path: []const u8,
    basename: []const u8,
    opts: anytype,
) !void {
    std.debug.print(
        "bfbs_path={s} gen_path={s} basename={s}\n",
        .{ bfbs_path, gen_path, basename },
    );
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const dirname_len = if (std.fs.path.dirname(basename)) |dirname|
        dirname.len + 1
    else
        0;
    const file_ident = try std.fmt.bufPrint(&buf, "//{s}.fbs", .{basename[dirname_len..]});
    const f = try std.fs.cwd().openFile(bfbs_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(alloc, std.math.maxInt(u16));
    defer alloc.free(content);
    const schema = Schema.GetRootAs(content, 0);
    // const writer = zig_file.writer();
    var needs_imports = false;
    var one_file_code = std.ArrayList(u8).init(alloc);
    const owriter = one_file_code.writer();

    for (0..schema.EnumsLen()) |i| {
        const e = schema.Enums(i).?;
        const same_file = mem.eql(u8, e.DeclarationFile().?, file_ident);
        if (!same_file) continue;
        // std.log.info("//writing enum {s} {?s}", .{ e.Name(), e.DeclarationFile() });
        var enumcode: std.ArrayListUnmanaged(u8) = .{};
        defer enumcode.deinit(alloc);
        const ewriter = enumcode.writer(alloc);
        try genPrelude(bfbs_path, e.DeclarationFile().?, basename, ewriter);
        try genEnum(e, schema, ewriter);
        if (e.IsUnion()) {
            try genNativeUnion(e, schema, ewriter);
            try genNativeUnionPack(e, ewriter);
            try genNativeUnionUnpack(e, schema, ewriter);
            _ = try ewriter.write("};\n\n");
        }
        // enum end

        if (opts.@"gen-onefile")
            _ = try owriter.write(enumcode.items)
        else
            try saveType(gen_path, e.Name(), enumcode.items, needs_imports, .enum_);
    }
    for (0..schema.ObjectsLen()) |i| {
        const o = schema.Objects(i).?;
        const same_file = mem.eql(u8, o.DeclarationFile().?, file_ident);
        if (!same_file) continue;
        std.log.info("//writing struct {s} {?s}", .{ o.Name(), o.DeclarationFile() });
        var structcode: std.ArrayListUnmanaged(u8) = .{};
        defer structcode.deinit(alloc);
        const swriter = structcode.writer(alloc);
        try genPrelude(bfbs_path, o.DeclarationFile().?, basename, swriter);
        try genStruct(o, schema, swriter, !opts.@"no-gen-object-api");
        if (opts.@"gen-onefile")
            _ = try owriter.write(structcode.items)
        else
            try saveType(gen_path, o.Name(), structcode.items, needs_imports, .struct_);
    }

    std.debug.print("{s}\n", .{one_file_code.items});
    // const zig_filename = try std.mem.concat(alloc, u8, &.{ basename, ".fb.zig" });
    // const zig_filepath = try std.fs.path.join(alloc, &.{ gen_path, zig_filename });
    // const zig_file = try std.fs.cwd().createFile(zig_filepath, .{});
    // defer zig_file.close();
}
