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
const TypenameSet = std.StringHashMap(BaseType);
const debug = true;

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
        .VECTOR, .STRUCT, .UNION, .ARRAY, .UTYPE, .NONE => common.panicf("zigScalarTypename() unexpected type: {}", .{base_type}),
    };
}

pub const scalar_sizes = blk: {
    const tags = std.meta.tags(BaseType);
    var result: [tags.len]?u32 = undefined;
    inline for (tags, 0..) |tag, i| {
        result[i] = switch (tag) {
            .NONE => 0,
            .BOOL => 1,
            .CHAR => 1,
            .UCHAR => 1,
            .SHORT => 2,
            .USHORT => 2,
            .INT => 4,
            .UINT => 4,
            .LONG => 8,
            .ULONG => 8,
            .FLOAT => 4,
            .DOUBLE => 8,
            .STRING => 16,
            else => null,
        };
    }
    break :blk result;
};

fn lastName(namespaced_name: []const u8) []const u8 {
    const last_dot = if (std.mem.lastIndexOfScalar(u8, namespaced_name, '.')) |i| i + 1 else 0;
    return namespaced_name[last_dot..];
}

const TypeFmt = struct {
    ty: Type,
    schema: Schema,
    mode: Mode,
    imports: *TypenameSet,

    const Mode = enum { skip_ns, keep_ns };

    pub fn init(
        ty: Type,
        schema: Schema,
        mode: TypeFmt.Mode,
        imports: *TypenameSet,
    ) TypeFmt {
        return .{
            .ty = ty,
            .schema = schema,
            .mode = mode,
            .imports = imports,
        };
    }

    /// write a type name to writer. adds enum and struct names to `imports`
    /// mode:
    ///   .keep_ns: fully qualified
    ///   .skip_ns: only write the last name component
    pub fn format(
        tnf: TypeFmt,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const ty = tnf.ty;
        const schema = tnf.schema;
        const mode = tnf.mode;
        const imports = tnf.imports;
        const base_ty = ty.BaseType();
        if (base_ty.isScalar() and ty.Index() != -1 or base_ty == .UNION) {
            const e = schema.Enums(@intCast(u32, ty.Index())).?;
            const name = switch (mode) {
                .keep_ns => e.Name(),
                .skip_ns => lastName(e.Name()),
            };
            try imports.put(e.Name(), base_ty);
            _ = try writer.write(name);
        } else if (base_ty.isScalar() or base_ty == .STRING)
            _ = try writer.write(zigScalarTypename(base_ty))
        else if (base_ty.isStruct()) {
            const o = schema.Objects(@intCast(u32, ty.Index())).?;
            const name = switch (mode) {
                .keep_ns => o.Name(),
                .skip_ns => lastName(o.Name()),
            };
            try imports.put(o.Name(), base_ty);
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
                    .keep_ns => o.Name(),
                    .skip_ns => lastName(o.Name()),
                };
                try imports.put(o.Name(), ele);
                _ = try writer.write(name);
            } else todo("TypeFmt.init() base_ty={} ele={}", .{ base_ty, ele });
        } else todo("TypeFmt.init() base_ty={}", .{base_ty});
    }
};

/// Create a type for the enum values.
fn genEnumType(
    e: Enum,
    writer: anytype,
    schema: Schema,
    base_type: BaseType,
    imports: *TypenameSet,
) !void {
    try writer.print("pub const {}", .{TypeFmt.init(
        e.UnderlyingType().?,
        schema,
        .skip_ns,
        imports,
    )});
    if (base_type.isUnion() or base_type == .UTYPE)
        _ = try writer.write(" = union(enum) {\n")
    else
        try writer.print(
            " = enum({s}) {{\n",
            .{zigScalarTypename(base_type)},
        );
}

/// A single enum member.
fn enumMember(_: Enum, ev: EnumVal, writer: anytype) !void {
    try writer.print("  {s} = {},\n", .{ ev.Name(), ev.Value() });
}
/// A single union member.
fn unionMember(_: Enum, ev: EnumVal, schema: Schema, writer: anytype) !void {
    if (ev.Value() == 0) {
        try writer.print("  {s},\n", .{ev.Name()});
        return;
    }
    try writer.print("  {s}: ", .{ev.Name()});
    const idx = ev.UnionType().?.Index();
    if (idx == -1) common.panicf("TODO ev.Name()={s}", .{ev.Name()});
    const e = schema.Objects(@bitCast(u32, idx)).?;
    try writer.print("{s},\n", .{e.Name()});
}

fn genEnum(
    e: Enum,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    // Generate enum declarations.
    // TODO check if already generated
    try genComment(e, writer);
    const base_type = e.UnderlyingType().?.BaseType();
    try genEnumType(e, writer, schema, base_type, imports);
    {
        var i: u32 = 0;
        while (i < e.ValuesLen()) : (i += 1) {
            const ev = e.Values(i).?;
            try genComment(ev, writer);
            if (base_type.isUnion() or base_type == .UTYPE)
                try unionMember(e, ev, schema, writer)
            else
                try enumMember(e, ev, writer);
        }
    }
    if (e.IsUnion())
        _ = try writer.write("\n\npub const Tag = std.meta.Tag(@This());\n");

    try writer.print(
        \\pub fn tagName(v: @This()) []const u8 {{
        \\  return @tagName(v);
        \\}}
        \\}};
        \\
        \\
    , .{});
}

/// gen a union(E) decl
fn genNativeUnion(
    e: Enum,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print("pub const {s}T = union({s}) {{\n", .{ last_name, last_name });
    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        try writer.print("{s}: {},\n", .{ ev.Name(), TypeFmt.init(
            ev.UnionType().?,
            schema,
            .keep_ns,
            imports,
        ) });
    }
}

/// gen a union pack() method
fn genNativeUnionPack(e: Enum, writer: anytype) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print(
        \\
        \\pub fn pack(rcv: {s}T, __builder: *Builder) !void {{
        \\  switch (rcv) {{
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
            try writer.print("    .{s} => |x| try x.pack(__builder),\n", .{ev.Name()});
    }
    _ = try writer.write(
        \\  }
        \\}
        \\
        \\
    );
}

/// gen a union unpack() method
fn genNativeUnionUnpack(e: Enum, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print(
        \\pub fn unpack(rcv: {s}, table: fb.Table, __pack_opts: fb.common.PackOptions) {s}T {{
        \\_ = .{{__pack_opts}};
        \\  switch (rcv) {{
        \\
    ,
        .{ last_name, last_name },
    );
    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        if (ev.Value() == 0)
            try writer.print(".{s} => return .{s},\n", .{ ev.Name(), ev.Name() })
        else {
            try writer.print(".{s} => {{\n", .{ev.Name()});

            const fty_fmt = TypeFmt.init(ev.UnionType().?, schema, .keep_ns, imports);
            try writer.print(
                \\var x = {}.init(table.bytes, table.pos);
                \\return .{{ .{s} = x.unpack(__pack_opts) }};
                \\}},
                \\
            , .{ fty_fmt, ev.Name() });
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

fn typenameToPath(
    buf: []u8,
    path_prefix: []const u8,
    typename: []const u8,
    file_extension: []const u8,
) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer();
    if (path_prefix.len != 0) {
        _ = try writer.write(path_prefix);
        try writer.writeByte(std.fs.path.sep);
    }
    for (typename) |c| {
        try writer.writeByte(if (c == '.') '/' else c);
    }
    if (file_extension.len != 0) {
        _ = try writer.write(file_extension);
    }
    return fbs.getWritten();
}

/// Save out the generated code to a .fb.zig file
fn saveType(
    gen_path: []const u8,
    bfbs_path: []const u8,
    decl_file: []const u8,
    basename: []const u8,
    typename: []const u8,
    contents: []const u8,
    needs_imports: bool,
    imports: TypenameSet,
    kind: enum { enum_, struct_ },
) !void {
    if (contents.len == 0) return;

    _ = .{ needs_imports, kind };
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const outpath = try typenameToPath(&buf, gen_path, typename, ".fb.zig");
    std.fs.cwd().makePath(std.fs.path.dirname(outpath).?) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("couldn't make dir {?s}", .{std.fs.path.dirname(outpath)});
            return e;
        },
    };
    const f = try std.fs.cwd().createFile(outpath, .{});
    defer f.close();
    try genPrelude(bfbs_path, decl_file, basename, typename, imports, f.writer());
    _ = try f.write(contents);
}

const NsEntry = union(enum) {
    leaf: BaseType,
    node: Map,

    pub const Map = std.StringHashMapUnmanaged(NsEntry);

    pub fn deinit(alloc: mem.Allocator, map: *NsEntry.Map) void {
        var iter = map.iterator();
        while (iter.next()) |it| {
            if (it.value_ptr.* == .node) deinit(alloc, &it.value_ptr.node);
        }
        map.deinit(alloc);
    }
};

fn populateNs(
    alloc: mem.Allocator,
    nsmap: *NsEntry.Map,
    ns: []const u8,
    base_ty: BaseType,
) !void {
    // std.debug.print("populateNs() ns={s}\n", .{ns});
    if (mem.indexOfScalar(u8, ns, '.')) |idx| {
        const root = ns[0..idx];
        const rest = ns[idx + 1 ..];
        const gop = try nsmap.getOrPut(alloc, root);
        if (gop.found_existing) {
            if (gop.value_ptr.* != .leaf)
                try populateNs(alloc, &gop.value_ptr.node, rest, base_ty)
            else
                // nothing to do if this is a leaf
                std.debug.assert(rest.len == 0);
        } else {
            gop.value_ptr.* = .{ .node = .{} };
            try populateNs(alloc, &gop.value_ptr.node, rest, base_ty);
        }
    } else {
        std.debug.assert(ns.len != 0);
        try nsmap.put(alloc, ns, .{ .leaf = base_ty });
    }
}

fn commonNsPrefixLen(a: []const u8, b: []const u8) usize {
    var iter = mem.split(u8, a, ".");
    var pos: usize = 0;
    var mnext = iter.next();
    while (mnext) |it| : (pos += it.len) {
        if (!mem.eql(u8, it, b[pos..][0..it.len])) return pos;
        mnext = iter.next();
        pos += @boolToInt(mnext != null); // don't advance pos past the end of a
    }
    return pos;
}

const NsTmpArr = std.BoundedArray(u8, std.fs.MAX_NAME_BYTES);

pub fn RepeatedFmt(comptime rep: []const u8, comptime sep: u8) type {
    return struct {
        times: usize,
        pub fn format(
            value: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            for (0..value.times) |_| {
                _ = try writer.write(rep);
                try writer.writeByte(sep);
            }
        }
    };
}

fn writeNs(
    nsmap: NsEntry.Map,
    writer: anytype,
    path_buf: *NsTmpArr,
    typename: []const u8,
    depth: u8,
) !void {
    var iter = nsmap.iterator();
    while (iter.next()) |it| {
        const full_name = it.key_ptr.*;
        if (debug) try writer.print(
            "// writeNs() key={s} tag={s} path_buf={s}\n",
            .{ full_name, @tagName(it.value_ptr.*), path_buf.constSlice() },
        );
        const extension = ".fb.zig";
        const common_prefix_len = commonNsPrefixLen(path_buf.constSlice(), typename);

        switch (it.value_ptr.*) {
            .leaf => |base_ty| {
                if (debug) try writer.print(
                    \\// typename={s} name={s} path_buf={s} common_prefix_len={} base_ty={s}
                    \\
                , .{ typename, full_name, path_buf.constSlice(), common_prefix_len, @tagName(base_ty) });
                if (path_buf.len > 0) {
                    var buf: [path_buf.buffer.len]u8 = undefined;
                    for (path_buf.constSlice(), 0..) |c, i| {
                        buf[i] = if (c == '.') '/' else c;
                    }
                    const path = if (common_prefix_len < path_buf.len)
                        buf[common_prefix_len..path_buf.len]
                    else
                        buf[0..0];

                    const dots = if (path.len > 0)
                        mem.count(u8, path, "/")
                    else
                        mem.count(u8, typename[common_prefix_len..], ".");

                    if (debug) try writer.print(
                        \\// path_buf.len={}, dots={}, path={s}
                        \\
                    , .{ path_buf.len, dots, path });

                    if (depth != 0) _ = try writer.write("pub ");
                    const dotsfmt = RepeatedFmt("..", std.fs.path.sep){ .times = dots };
                    try writer.print(
                        \\const {0s} = @import("{3}{1s}{0s}{2s}").{0s};
                        \\
                    , .{ full_name, path, extension, dotsfmt });
                    if (base_ty == .STRUCT)
                        try writer.print(
                            \\const {0s}T = @import("{3}{1s}{0s}{2s}").{0s}T;
                            \\
                        , .{ full_name, path, extension, dotsfmt });
                } else {
                    const same = mem.eql(u8, full_name, lastName(typename));
                    if (debug) try writer.print(
                        \\// path_buf.len == 0
                        \\// same={}
                        \\
                    , .{same});
                    if (!same) {
                        const dots = mem.count(u8, typename, ".");
                        if (depth != 0) _ = try writer.write("pub ");
                        const dots_fmt = RepeatedFmt("..", std.fs.path.sep){ .times = dots };
                        try writer.print(
                            \\const {0s} = @import("{2}{0s}{1s}").{0s};
                            \\
                        , .{ full_name, extension, dots_fmt });
                        if (base_ty == .STRUCT)
                            try writer.print(
                                \\const {0s}T = @import("{2}{0s}{1s}").{0s}T;
                                \\
                            , .{ full_name, extension, dots_fmt });
                    }
                }
            },
            .node => |map| {
                if (depth != 0) _ = try writer.write("pub ");
                try writer.print(
                    \\const {0s} = struct {{
                    \\
                , .{full_name});
                const len = path_buf.len;
                defer path_buf.len = len;
                try path_buf.appendSlice(full_name);
                try path_buf.append('.');
                try writeNs(map, writer, path_buf, typename, depth + 1);
                _ = try writer.write("\n};\n");
            },
        }
    }
}

fn genPrelude(
    bfbs_path: []const u8,
    file_ident: []const u8,
    basename: []const u8,
    typename: []const u8,
    imports: TypenameSet,
    writer: anytype,
) !void {
    try writer.print(
        \\//!
        \\//! generated by flatc-zig
        \\//! binary:     {s}
        \\//! schema:     {s}.fbs
        \\//! file ident: {?s}
        \\//! typename    {?s}
        \\//!
        \\
        \\const std = @import("std");
        \\const fb = @import("flatbufferz");
        \\const Builder = fb.Builder;
        \\
        \\
    , .{ bfbs_path, basename, file_ident, typename });
    var nsroot = NsEntry.Map{};
    defer NsEntry.deinit(imports.allocator, &nsroot);
    {
        var iter = imports.iterator();
        while (iter.next()) |it| {
            const name = it.key_ptr.*;
            try populateNs(imports.allocator, &nsroot, name, it.value_ptr.*);
        }
    }
    var arr = NsTmpArr{};
    try writeNs(nsroot, writer, &arr, typename, 0);
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
    try writer.print(
        \\pub fn pack(rcv: {s}T, __builder: *Builder, __pack_opts: fb.common.PackOptions) !u32 {{
        \\_ = .{{__pack_opts}};
        \\
    , .{struct_type});
    {
        const fields_len = o.FieldsLen();
        if (fields_len == 0) _ = try writer.write("_ = rcv;\n");
        var i: u32 = 0;
        while (i < fields_len) : (i += 1) {
            const field = o.Fields(i).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            if (field_base_ty.isScalar()) continue;
            const fname_orig = field.Name();
            const fname_off = FmtWithSuffix("_off"){ .name = fname_orig };
            if (field_base_ty == .STRING) {
                try writer.print(
                    \\const {0s} = if (rcv.{1s}.items.len != 0) try __builder.createString(rcv.{1s}) else 0;
                    \\
                , .{ fname_off, fieldName(fname_orig) });
            } else if (field_base_ty.isVector() and
                field_ty.Element() == .UCHAR and
                !field_base_ty.isUnion())
            {
                try writer.print(
                    \\const {0s} = if (rcv.{1s}.items.len != 0)
                    \\  try __builder.createByteString(rcv.{1s})
                    \\else
                    \\  0;
                    \\
                , .{ fname_off, fieldName(fname_orig) });
            } else if (field_base_ty.isVector()) {
                const fname_len = FmtWithSuffix("_len"){ .name = fname_orig };
                try writer.print(
                    \\var {0s}: u32 = 0;
                    \\if (rcv.{1s}.items.len != 0) {{
                    \\const {2s} = rcv.{1s}.items.len;
                    \\
                , .{ fname_off, fieldName(fname_orig), fname_len });
                const fty_ele = field_ty.Element();
                const fname_offsets = FmtWithSuffix("_offsets"){ .name = fname_orig };
                if (fty_ele == .STRING) {
                    try writer.print(
                        \\var {0s} = try std.ArrayListUnmanaged(u32).initCapacity(__pack_opts.allocator.?, {1s});
                        \\defer {0s}.deinit();
                        \\for ({0s}.items, 0..) |*off, j| {{
                        \\off.* = try __builder.createString(rcv.{2s}[j]);
                        \\}}
                        \\
                    , .{ fname_offsets, fname_len, fieldName(fname_orig) });
                } else if (fty_ele == .STRUCT and isStruct(field_ty.Index(), schema)) {
                    try writer.print(
                        \\var {0s} = try std.ArrayListUnmanaged(u32).initCapacity(__pack_opts.allocator.?, {1s});
                        \\defer {0s}.deinit();
                        \\for ({0s}.items, 0..) |*off, j| {{
                        \\off.* = try rcv.{2s}[j].pack(__builder);
                        \\}}
                        \\
                    , .{ fname_offsets, fname_len, fieldName(fname_orig) });
                }

                const fname_camel_upper = util.fmtCamelUpper(fname_orig);
                try writer.print(
                    \\try {s}.Start{}Vector(__builder, {2s});
                    \\{{
                    \\var j = {3s} - 1;
                    \\while (true) : (j -= 1) {{
                    \\
                , .{ struct_type, fname_camel_upper, fname_off, fname_len });
                if (fty_ele.isScalar()) {
                    try writer.print(
                        "try __builder.prepend({s}, rcv.{s}[j]);\n",
                        .{ zigScalarTypename(fty_ele), fieldName(fname_orig) },
                    );
                } else if (fty_ele == .STRUCT and isStruct(field_ty.Index(), schema)) {
                    try writer.print("try __builder.prependUOff({s}[j]);\n", .{fname_offsets});
                } else {
                    try writer.print("try rcv.{s}[j].pack(__builder);\n", .{fieldName(fname_orig)});
                }
                try writer.print(
                    \\if (j == 0) break;
                    \\}}
                    \\{0s} = __builder.endVector({1s});
                    \\}}
                    \\}}
                    \\
                , .{ fname_off, fname_len });
            } else if (field_base_ty == .STRUCT) {
                if (isStruct(field_ty.Index(), schema)) continue;
                try writer.print(
                    "const {0s} = try rcv.{1s}.pack(__builder);\n",
                    .{ fname_off, fieldName(fname_orig) },
                );
            } else if (field_base_ty == .UNION) {
                try writer.print(
                    "const {0s} = try rcv.{1s}.pack(__builder);\n",
                    .{ fname_off, fieldName(fname_orig) },
                );
            } else unreachable;
        }
    }

    try writer.print("{s}.Start(__builder);\n", .{struct_type});

    {
        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(i).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            const fname_orig = field.Name();
            const fname_off = FmtWithSuffix("_off"){ .name = fname_orig };
            const fname_camel_upper = util.fmtCamelUpper(fname_orig);
            if (field_base_ty.isScalar()) {
                const is_optional = hasAttribute(field, "optional");
                if (is_optional) todo("optional", .{});
                if (field_base_ty != .UNION)
                    try writer.print(
                        "try {s}.Add{s}(__builder, rcv.{s});\n",
                        .{ struct_type, fname_camel_upper, fieldName(fname_orig) },
                    );

                if (is_optional) todo("optional", .{});
            } else {
                if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema)) {
                    try writer.print(
                        "const {0s} = try rcv.{1s}.pack(__builder);\n",
                        .{ fname_off, fieldName(fname_orig) },
                    );
                } else if (field_base_ty == .UNION) {
                    try writer.print(
                        "try {s}.Add{s}T(__builder, rcv.{s});\n",
                        .{ struct_type, fname_camel_upper, fieldName(fname_orig) },
                    );
                }
                try writer.print(
                    "{s}.Add{s}(__builder, {s});\n",
                    .{ struct_type, fname_camel_upper, fname_off },
                );
            }
        }
    }
    try writer.print("return {s}.End(__builder);\n}}\n\n", .{struct_type});
}

fn genNativeTableUnpack(
    o: Object,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const oname = o.Name();
    const struct_type = lastName(oname);
    try writer.print(
        \\pub fn unpackTo(rcv: {s}, t: *{s}T, __pack_opts: fb.common.PackOptions) !void {{
        \\_ = .{{__pack_opts}};
        \\
    ,
        .{ struct_type, struct_type },
    );
    {
        const fields_len = o.FieldsLen();
        if (fields_len == 0) _ = try writer.write("_ = rcv;\n_ = t;\n");
        var i: u32 = 0;
        while (i < fields_len) : (i += 1) {
            const field = o.Fields(i).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            const fname = fieldName(field.Name());
            const fname_upper_camel = util.fmtCamelUpper(field.Name());
            if (debug) try writer.print(
                \\// {s}: {}() {s} {?} field_ty.Index()={}
                \\
            , .{
                fname,
                fname_upper_camel,
                @tagName(field_base_ty),
                field_ty.Element(),
                field_ty.Index(),
            });
            if (mem.endsWith(u8, fname, "_type") and field_base_ty == .UTYPE)
                continue;
            const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
            if ((field_base_ty.isScalar() or field_base_ty == .STRING) and
                field_base_ty != .UNION)
            {
                try writer.print(
                    "t.{s} = rcv.{s}();\n",
                    .{ fname, fname_upper_camel },
                );
            } else if (field_base_ty == .VECTOR and
                field_ty.Element() == .UCHAR and
                field_ty.Index() == -1)
            {
                try writer.print(
                    \\// TODO .VECTOR .UCHAR
                    \\// t.{s} = rcv.{s}Bytes();
                    \\
                ,
                    .{ fname, fname_upper_camel },
                );
            } else if (field_base_ty == .VECTOR) {
                const fname_len = FmtWithSuffix("_len"){ .name = field.Name() };
                const ele = field_ty.Element();
                if (ele == .STRUCT)
                    try writer.print(
                        \\const {3} = rcv.{1s}Len();
                        \\t.{0s} = try std.ArrayListUnmanaged({2}T).initCapacity(__pack_opts.allocator.?, {3});
                        \\{{
                        \\var j: u32 = 0;
                        \\while (j < {3}) : (j += 1) {{
                        \\const x = rcv.{1}(j).?;
                        \\
                        \\
                    , .{ fname, fname_upper_camel, fty_fmt, fname_len })
                else
                    try writer.print(
                        \\const {3} = rcv.{1s}Len();
                        \\t.{0s} = try std.ArrayListUnmanaged({2}).initCapacity(__pack_opts.allocator.?, {3});
                        \\{{
                        \\var j: u32 = 0;
                        \\while (j < {3}) : (j += 1) {{
                        \\
                    , .{ fname, fname_upper_camel, fty_fmt, fname_len });

                try writer.print("t.{s}.appendAssumeCapacity(", .{fname});
                if (field_ty.Element().isScalar()) {
                    try writer.print("rcv.{s}(j)", .{fname_upper_camel});
                } else if (field_ty.Element() == .STRING) {
                    try writer.print("rcv.{s}(j)", .{fname_upper_camel});
                } else if (field_ty.Element() == .STRUCT) {
                    try writer.print("try {}T.unpack(x, __pack_opts)", .{fty_fmt});
                } else {
                    // TODO(iceboy): Support vector of unions.
                    unreachable;
                }
                _ = try writer.write(
                    \\);
                    \\}
                    \\}
                    \\
                );
            } else if (field_base_ty == .STRUCT) {
                try writer.print(
                    \\if (rcv.{0}()) |x| {{
                    \\if (t.{2s} == null) t.{2s} = try __pack_opts.allocator.?.create({1}T);
                    \\try {1}T.unpackTo(x, t.{2s}.?, __pack_opts);
                    \\}}
                    \\
                , .{ fname_upper_camel, fty_fmt, fname });
            } else if (field_base_ty == .UNION) {
                try writer.print(
                    \\// unpack union
                    \\// if (rcv.{1s}()) |_tab| {{
                    \\// t.{0s} = try {1s}T.unpack(rcv, _tab, __pack_opts); // FIXME can't be right
                    \\// }}
                    \\
                , .{ fname, fname_upper_camel });
            } else unreachable;
        }
    }

    _ = try writer.write("}\n\n");
    try writer.print(
        \\pub fn unpack(rcv: {0s}, __pack_opts: fb.common.PackOptions) fb.common.PackError!{0s}T {{
        \\var t = {0s}T{{}};
        \\try {0s}T.unpackTo(rcv, &t, __pack_opts);
        \\return t;
        \\}}
        \\
        \\
    , .{struct_type});
}

fn genNativeStructPack(o: Object, schema: Schema, writer: anytype) !void {
    const olastname = lastName(o.Name());
    try writer.print(
        \\pub fn pack(rcv: {0s}, __builder: *Builder) !void {{
        \\return {0s}.Create(__builder
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

fn genNativeStructUnpack(o: Object, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    const olastname = lastName(o.Name());
    try writer.print(
        \\pub fn unpackTo(rcv: {0s}, t: *{0s}T, __pack_opts: fb.common.PackOptions) !void {{
        \\_ = .{{__pack_opts}};
        \\
    , .{olastname});
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        const field_ty = field.Type().?;
        const fname = fieldName(field.Name());
        const fname_camel_upper = util.fmtCamelUpper(field.Name());

        if (field_ty.BaseType() == .STRUCT) {
            const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
            try writer.print(
                \\if (t.{0s} == null) {{ t.{0s} = try __pack_opts.allocator.?.create({1}T); }}
                \\t.{0s}.?.* = try {1}T.unpack(rcv.{2}(), __pack_opts);
                \\
            , .{ fname, fty_fmt, fname_camel_upper });
        } else try writer.print(
            "t.{s} = rcv.{s}();\n",
            .{ fname, fname_camel_upper },
        );
    }

    try writer.print(
        \\}}
        \\
        \\pub fn unpack(rcv: {0s}, __pack_opts: fb.common.PackOptions) !{0s}T {{
        \\var t = {0s}T{{}};
        \\try {0s}T.unpackTo(rcv, &t, __pack_opts);
        \\return t;
        \\}}
        \\
        \\
    , .{olastname});
}

fn genNativeStruct(o: Object, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
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
        const fname = field.Name();
        if (field_base_ty == .UTYPE and mem.endsWith(u8, fname, "_type")) continue;

        _ = try writer.write(fieldName(fname));
        _ = try writer.write(": ");
        const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
        if (field_base_ty.isVector()) {
            const ele = field_ty.Element();
            try writer.print("std.ArrayListUnmanaged({}", .{fty_fmt});
            if (ele == .STRUCT) _ = try writer.write("T");
            _ = try writer.write(") = .{}");
        } else {
            // gen field type
            if (field_base_ty == .STRUCT) _ = try writer.write("?*");
            try writer.print("{}", .{fty_fmt});
            // gen field default value
            if (field_base_ty == .STRUCT)
                _ = try writer.write("T = null")
            else if (field_base_ty == .UNION) {
                try writer.print(" = @intToEnum({}.Tag , 0)", .{fty_fmt});
            } else if (field_base_ty == .STRING) {
                _ = try writer.write(" = \"\"");
            } else {
                _ = try writer.write(" = ");
                const field_ty_idx = field_ty.Index();
                if (field_ty_idx == -1)
                    try genConstant(field, field_base_ty, schema, imports, writer)
                else { // this is an enum type. use DefaultInteger() or else undefined
                    if (field.HasDefaultInteger()) {
                        try writer.print(
                            "@intToEnum({}, {})",
                            .{ fty_fmt, field.DefaultInteger() },
                        );
                    } else _ = try writer.write("undefined");
                }
            }
        }
        _ = try writer.write(",\n");
    }
    _ = try writer.write("\n");
    if (!o.IsStruct()) {
        try genNativeTablePack(o, schema, writer);
        try genNativeTableUnpack(o, schema, imports, writer);
    } else {
        try genNativeStructPack(o, schema, writer);
        try genNativeStructUnpack(o, schema, imports, writer);
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
        \\const n = fb.encode.read(u32, buf[offset..]);
        \\return {0s}.init(buf, n+offset);
        \\}}
        \\
        \\
    , .{o.Name()});
}

fn initializeExisting(o: Object, writer: anytype) !void {
    // Initialize an existing object with other data, to avoid an allocation.
    if (o.IsStruct())
        try writer.print(
            \\pub fn init(bytes: []const u8, pos: u32) {s} {{
            \\return .{{ ._tab = .{{ ._tab = .{{ .bytes = bytes, .pos = pos }}}}}};
            \\}}
            \\
            \\
        , .{lastName(o.Name())})
    else
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
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    try writer.print(
        \\pub fn {s}Len(rcv: {s}) u32 
    , .{ fname_camel_upper, lastName(o.Name()) });
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
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    try writer.print(
        \\pub fn {s}Bytes(rcv: {s}) []const u8
    , .{ fname_camel_upper, lastName(o.Name()) });
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
fn genGetter(
    ty: Type,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    switch (ty.BaseType()) {
        .STRING => _ = try writer.write("rcv._tab.byteVector("),
        .UNION => _ = try writer.write("rcv._tab.union_("),
        .VECTOR => switch (ty.Element()) {
            .STRING => _ = try writer.write("rcv._tab.byteVector("),
            .UNION => _ = try writer.write("rcv._tab.union_("),
            .VECTOR => todo(".VECTOR .VECTOR", .{}),
            else => |ele| {
                _ = try writer.write("rcv._tab.read(");
                if (ele.isScalar() or ele == .STRING) {
                    _ = try writer.write(zigScalarTypename(ele));
                    _ = try writer.write(", ");
                } else todo("genGetter .VECTOR {}", .{ele});
            },
        },
        else => |base_ty| {
            try writer.print("rcv._tab.read({}", .{
                TypeFmt.init(ty, schema, .keep_ns, imports),
            });
            if (base_ty.isUnion() or base_ty == .UTYPE)
                _ = try writer.write(".Tag");
            _ = try writer.write(", ");
        },
    }
}

/// Most field accessors need to retrieve and test the field offset first,
/// this is the prefix code for that.
fn offsetPrefix(field: Field, writer: anytype) !void {
    try writer.print(
        \\ {{
        \\const o = rcv._tab.offset({});
        \\if (o != 0) {{
        \\
    , .{field.Offset()});
}

fn isScalarOptional(field: Field, field_base_ty: BaseType) bool {
    return field_base_ty.isScalar() and field.Optional();
}

fn genConstant(
    field: Field,
    field_base_ty: BaseType,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    if (debug) try writer.print(
        \\// genConstant() field.Name()={s} field_base_ty={}
        \\
    , .{ field.Name(), field_base_ty });
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
        .FLOAT => {
            const default_real = field.DefaultReal();
            if (std.math.isNan(default_real))
                _ = try writer.write("std.math.nan(f32)")
            else if (std.math.isInf(default_real))
                _ = try writer.write("std.math.inf(f32)")
            else if (std.math.isNegativeInf(default_real))
                _ = try writer.write("-std.math.inf(f32)")
            else
                try writer.print("{}", .{default_real});
        },
        .DOUBLE => {
            const default_real = field.DefaultReal();
            if (std.math.isNan(default_real))
                _ = try writer.write("std.math.nan(f64)")
            else if (std.math.isInf(default_real))
                _ = try writer.write("std.math.inf(f64)")
            else if (std.math.isNegativeInf(default_real))
                _ = try writer.write("-std.math.inf(f64)")
            else
                try writer.print("{}", .{default_real});
        },
        // FIXME: ? not sure about these values, just copied go ouptut
        .STRUCT, .VECTOR => _ = try writer.write("0"),
        else => {
            const field_ty = field.Type().?;
            const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
            if (field_ty.Index() == -1)
                try writer.print("{}", .{field.DefaultInteger()})
            else if (field_base_ty == .UTYPE) {
                try writer.print("@intToEnum({}.Tag, {})", .{
                    fty_fmt,
                    field.DefaultInteger(),
                });
            } else if (field_base_ty.isInteger()) {
                try writer.print("@intToEnum({}, {})", .{
                    fty_fmt,
                    field.DefaultInteger(),
                });
            } else {
                try writer.print("{}", .{field.DefaultInteger()});
            }
        },
    }
}

const NamePrefix = std.BoundedArray(u8, std.fs.MAX_NAME_BYTES);

/// Recursively generate arguments for a constructor, to deal with nested
/// structs.
fn structBuilderArgs(
    o: Object,
    nameprefix: *NamePrefix,
    alloc: mem.Allocator,
    arg_names: *std.StringHashMapUnmanaged(void),
    imports: *TypenameSet,
    schema: Schema,
    writer: anytype,
) !void {
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
            const len = nameprefix.len;
            defer nameprefix.len = len;
            try nameprefix.appendSlice(field.Name());
            try nameprefix.append('_');
            try structBuilderArgs(
                o2,
                nameprefix,
                alloc,
                arg_names,
                imports,
                schema,
                writer,
            );
        } else {
            const fname = fieldName(field.Name());
            var argname = std.ArrayList(u8).init(alloc);
            try argname.appendSlice(nameprefix.constSlice());
            try argname.appendSlice(fname);

            while (true) {
                const gop = try arg_names.getOrPut(alloc, argname.items);
                if (gop.found_existing)
                    try argname.append('_')
                else
                    break;
            }
            try writer.print(
                \\, {s}: {}
            , .{
                argname.items,
                TypeFmt.init(field_ty, schema, .keep_ns, imports),
            });
        }
    }
}

/// Writes the method name for use with add/put calls.
fn genMethod(
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    if (field_ty.BaseType().isScalar()) {
        try writer.print(
            "({}",
            .{TypeFmt.init(field_ty, schema, .keep_ns, imports)},
        );
        const field_base_ty = field_ty.BaseType();
        if (field_base_ty.isUnion() or field_base_ty == .UTYPE)
            _ = try writer.write(".Tag");
        _ = try writer.write(", ");
    } else _ = try writer.write(if (field_ty.BaseType() == .STRUCT and
        isStruct(field_ty.Index(), schema))
        "Struct("
    else
        "UOff(");
}

/// Recursively generate struct construction statements and instert manual
/// padding.
fn structBuilderBody(
    o: Object,
    nameprefix: *NamePrefix,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    try writer.print(
        \\try __builder.prep({}, {});
        \\
    , .{ o.Minalign(), o.Bytesize() });
    var i = @bitCast(i32, o.FieldsLen()) - 1;
    while (i >= 0) : (i -= 1) {
        const field = o.Fields(@bitCast(u32, i)).?;
        const padding = field.Padding();
        if (debug) try writer.print(
            \\// {s}.{s}: padding={} id={}
            \\
        , .{ lastName(o.Name()), field.Name(), padding, field.Id() });
        if (padding != 0)
            try writer.print(
                \\__builder.pad({});
                \\
            , .{padding});
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema)) {
            const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
            const len = nameprefix.len;
            defer nameprefix.len = len;
            try nameprefix.appendSlice(field.Name());
            try nameprefix.append('_');
            try structBuilderBody(o2, nameprefix, schema, imports, writer);
        } else {
            _ = try writer.write("try __builder.prepend");
            try genMethod(field, schema, imports, writer);
            try writer.print(
                \\ {s}{s});
                \\
            , .{ nameprefix.constSlice(), field.Name() });
        }
    }
}

/// Create a struct with a builder and the struct's arguments.
fn genStructBuilder(o: Object, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    _ = try writer.write(
        \\pub fn Create(__builder: *Builder
    );
    var nameprefix = NamePrefix{};
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var arg_names = std.StringHashMapUnmanaged(void){};
    try arg_names.put(alloc, "__builder", {});
    try structBuilderArgs(o, &nameprefix, alloc, &arg_names, imports, schema, writer);
    _ = try writer.write(") !u32 {\n");
    nameprefix.len = 0;
    try structBuilderBody(o, &nameprefix, schema, imports, writer);
    _ = try writer.write(
        \\return __builder.offset();
        \\}
        \\
    );
}

// Get the value of a table's starting offset.
fn getStartOfTable(o: Object, writer: anytype) !void {
    try writer.print(
        \\pub fn Start(__builder: *Builder) !void {{
        \\try __builder.startObject({});
        \\}}
        \\
    , .{o.FieldsLen()});
}

/// Generate table constructors, conditioned on its members' types.
fn genTableBuilders(
    o: Object,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    try getStartOfTable(o, writer);

    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(i).?;
        if (field.Deprecated()) continue;

        try buildFieldOfTable(
            o,
            field,
            schema,
            // FIXME: is this correct?
            (field.Offset() - 4) / 2,
            imports,
            writer,
        );
        if (field.Type().?.BaseType() == .VECTOR)
            try buildVectorOfTable(o, field, schema, writer);
    }

    try getEndOffsetOnTable(o, writer);
}

/// Get the value of a struct's scalar.
fn getScalarFieldOfStruct(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
    try writer.print(
        \\pub fn {}(rcv: {s}) {} {{
        \\return 
    , .{ fname_camel_upper, lastName(o.Name()), fty_fmt });
    try genGetter(field_ty, schema, imports, writer);
    try writer.print(
        \\rcv._tab._tab.pos + {});
        \\}}
        \\
    , .{field.Offset()});
}

/// Get the value of a struct's scalar.
fn getScalarFieldOfTable(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
    try writer.print(
        \\pub fn {s}(rcv: {s}) {}
    , .{ fname_camel_upper, lastName(o.Name()), fty_fmt });
    const field_base_ty = field_ty.BaseType();
    if (field_base_ty.isUnion() or field_base_ty == .UTYPE)
        _ = try writer.write(".Tag");
    try offsetPrefix(field, writer);
    if (isScalarOptional(field, field_base_ty)) {
        _ = try writer.write("const v = ");
    } else {
        _ = try writer.write("return ");
    }
    try genGetter(field_ty, schema, imports, writer);
    try writer.print(
        \\o + rcv._tab.pos);
        \\
    , .{});
    if (isScalarOptional(field, field_base_ty)) _ = try writer.write("\nreturn v;");
    _ = try writer.write(
        \\}
        \\return 
    );
    try genConstant(field, field_base_ty, schema, imports, writer);
    _ = try writer.write(
        \\;
        \\}
        \\
        \\
    );
}

fn getStringField(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const oname = o.Name();
    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
    try writer.print(
        \\pub fn {s}(rcv: {s}) {}
    , .{ fname_camel_upper, lastName(oname), fty_fmt });
    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\return 
    );
    try genGetter(field_ty, schema, imports, writer);
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
fn getStructFieldOfStruct(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const oname = o.Name();
    const fty_fmt = TypeFmt.init(field.Type().?, schema, .keep_ns, imports);
    try writer.print(
        \\pub fn {0s}(rcv: {1s}) {2} {{
        \\return {2}.init(rcv._tab._tab.bytes, rcv._tab._tab.pos + {3});
        \\}}
        \\
        \\
    , .{ fname_camel_upper, oname, fty_fmt, field.Offset() });
}

/// Get a struct by initializing an existing struct.
/// Specific to Table.
fn getStructFieldOfTable(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const oname = o.Name();
    // Get the value of a union from an object.
    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
    try writer.print(
        \\pub fn {s}(rcv: {s}) ?{}
    , .{ fname_camel_upper, lastName(oname), fty_fmt });
    try offsetPrefix(field, writer);
    const field_base_ty = field_ty.BaseType();
    if (field_base_ty == .STRUCT and isStruct(field_ty.Index(), schema))
        _ = try writer.write("const x = o + rcv._tab.pos;\n")
    else
        _ = try writer.write("const x = rcv._tab.indirect(o + rcv._tab.pos);\n");

    try writer.print(
        \\return {}.init(rcv._tab.bytes, x);
        \\}}
        \\return null;
        \\}}
        \\
        \\
    , .{fty_fmt});
}

fn getUnionField(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const oname = o.Name();

    // Get the value of a union from an object.
    try writer.print(
        \\pub fn {s}(rcv: {s}) ?fb.Table
    , .{ fname_camel_upper, lastName(oname) });
    _ = try writer.write("\n");
    try offsetPrefix(field, writer);
    _ = try writer.write("return ");
    try genGetter(field_ty, schema, imports, writer);
    _ = try writer.write(
        \\o);
        \\}
        \\return null;
        \\}
        \\
        \\
    );
}

fn inlineSize(ty: Type, schema: Schema) u32 {
    _ = schema;
    const base_ty = ty.BaseType();
    return switch (base_ty) {
        .VECTOR => if (scalar_sizes[@enumToInt(ty.Element())]) |scalar_size|
            scalar_size
        else switch (ty.Element()) {
            .STRUCT => ty.BaseSize(),
            .VECTOR => unreachable,
            .UNION => unreachable,
            .ARRAY => unreachable,
            .UTYPE => unreachable,
            else => unreachable,
        },

        else => common.panicf("TODO inlineSize() base_ty={}", .{base_ty}),
    };
}

/// Get the value of a vector's struct member.
fn getMemberOfVectorOfStruct(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const oname = o.Name();
    const o2 = schema.Objects(@bitCast(u32, field_ty.Index())).?;
    try writer.print(
        \\pub fn {s}(rcv: {s}, j: usize) ?{s} 
    , .{ fname_camel_upper, lastName(oname), o2.Name() });
    try offsetPrefix(field, writer);
    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
    try writer.print(
        \\  var x = rcv._tab.vector(o);
        \\  x += @intCast(u32, j) * {};
        \\  x = rcv._tab.indirect(x);
        \\  return {}
        \\.init(rcv._tab.bytes, x);
        \\}}
        \\return null;
        \\}}
        \\
        \\
    , .{ inlineSize(field_ty, schema), fty_fmt });
}

/// Get the value of a vector's non-struct member.
fn getMemberOfVectorOfNonStruct(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const oname = o.Name();

    try writer.print(
        \\pub fn {s}(rcv: {s}, j: usize) {s} 
    , .{ fname_camel_upper, lastName(oname), zigScalarTypename(field_ty.Element()) });

    _ = try writer.write(" ");

    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\  const a = rcv._tab.vector(o);
        \\  return 
    );

    try genGetter(field_ty, schema, imports, writer);
    try writer.print(
        \\a + @intCast(u32, j) * {});
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

var field_name_buf: [std.fs.MAX_NAME_BYTES]u8 = undefined;
fn fieldName(fname: []const u8) []const u8 {
    if (std.zig.Token.getKeyword(fname) != null or
        std.zig.primitives.isPrimitive(fname))
    {
        mem.copy(u8, &field_name_buf, "@\"");
        mem.copy(u8, field_name_buf[2..], fname);
        mem.copy(u8, field_name_buf[2 + fname.len ..], "\"");
        return field_name_buf[0 .. 3 + fname.len];
    }
    return fname;
}

fn FmtWithSuffix(comptime suffix: []const u8) type {
    return struct {
        name: []const u8,
        pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            var buf: [std.fs.MAX_NAME_BYTES]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            const bufwriter = fbs.writer();
            _ = bufwriter.write(value.name) catch return error.OutOfMemory;
            _ = bufwriter.write(suffix) catch return error.OutOfMemory;
            const full_name = fbs.getWritten();
            if (std.zig.Token.getKeyword(full_name) != null or
                std.zig.primitives.isPrimitive(full_name))
            {
                try writer.print(
                    \\@"{s}"
                , .{full_name});
            } else _ = try writer.write(full_name);
        }
    };
}

/// Set the value of a table's field.
fn buildFieldOfTable(
    o: Object,
    field: Field,
    schema: Schema,
    offset: u16,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname = fieldName(field.Name());
    const field_ty = field.Type().?;
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const field_base_ty = field_ty.BaseType();

    if (debug) try writer.print(
        \\//fname={s} field_base_ty={}
        \\
    , .{ fname, field_base_ty });

    try writer.print(
        \\pub fn Add{s}(__builder: *Builder, {s}: 
    , .{ fname_camel_upper, fname });

    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports);
    if (!field_base_ty.isScalar() and !o.IsStruct()) {
        _ = try writer.write("u32");
    } else if (field_base_ty.isUnion() or field_base_ty == .UTYPE) {
        try writer.print("{}.Tag", .{fty_fmt});
    } else {
        try writer.print("{}", .{fty_fmt});
    }

    if (field_base_ty.isStruct() and isStruct(field_ty.Index(), schema))
        _ = try writer.write(
            \\) void {
            \\__builder.prepend
        )
    else
        _ = try writer.write(
            \\) !void {
            \\try __builder.prepend
        );
    if (isScalarOptional(field, field_base_ty)) {
        _ = try writer.write("(");
    } else {
        _ = try writer.write("Slot");
        try genMethod(field, schema, imports, writer);
        try writer.print("{}, ", .{offset});
    }

    _ = try writer.write(fname);

    if (isScalarOptional(field, field_base_ty)) {
        try writer.print(
            \\)
            \\__builder.slot({}
        , .{offset});
    } else {
        _ = try writer.write(", ");
        try genConstant(field, field_base_ty, schema, imports, writer);
    }
    _ = try writer.write(
        \\);
        \\}
        \\
        \\
    );
}

/// Set the value of one of the members of a table's vector.
fn buildVectorOfTable(_: Object, field: Field, schema: Schema, writer: anytype) !void {
    const fname_camel_upper = util.fmtCamelUpper(field.Name());
    const field_ty = field.Type().?;
    const ele = field_ty.Element();
    const alignment = if (ele.isScalar() or ele == .STRING)
        scalar_sizes[@enumToInt(ele)].?
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
        \\pub fn Start{s}Vector(__builder: *Builder, num_elems: i32) !u32 {{
        \\return __builder.startVector({}, num_elems, {});
        \\}}
        \\
    , .{ fname_camel_upper, field_ty.ElementSize(), alignment });
}

/// Get the offset of the end of a table.
fn getEndOffsetOnTable(_: Object, writer: anytype) !void {
    try writer.print(
        \\pub fn End(__builder: *Builder) !u32 {{
        \\return __builder.endObject();
        \\}}
        \\
        \\
    , .{});
}

/// Generate a struct field getter, conditioned on its child type(s).
fn genStructAccessor(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    try genComment(field, writer);
    const field_ty = field.Type().?;
    const field_base_ty = field_ty.BaseType();

    if (field_base_ty.isScalar()) {
        if (o.IsStruct())
            try getScalarFieldOfStruct(
                o,
                field,
                schema,
                imports,
                writer,
            )
        else
            try getScalarFieldOfTable(
                o,
                field,
                schema,
                imports,
                writer,
            );
    } else {
        switch (field_base_ty) {
            .STRUCT => if (o.IsStruct())
                try getStructFieldOfStruct(o, field, schema, imports, writer)
            else
                try getStructFieldOfTable(o, field, schema, imports, writer),
            .STRING => try getStringField(o, field, schema, imports, writer),
            .VECTOR => {
                if (field_ty.Element() == .STRUCT) {
                    try getMemberOfVectorOfStruct(o, field, schema, imports, writer);
                    // TODO(michaeltle): Support querying fixed struct by key.
                    // Currently, we only support keyed tables.
                    const struct_def = schema.Objects(@bitCast(u32, field_ty.Index())).?;
                    if (!struct_def.IsStruct() and field.Key()) {
                        // try getMemberOfVectorOfStructByKey(o, field, writer);
                        todo("getMemberOfVectorOfStructByKey", .{});
                    }
                } else {
                    try getMemberOfVectorOfNonStruct(
                        o,
                        field,
                        schema,
                        imports,
                        writer,
                    );
                }
            },
            .UNION => try getUnionField(
                o,
                field,
                schema,
                imports,
                writer,
            ),
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
fn genStruct(
    o: Object,
    schema: Schema,
    gen_obj_based_api: bool,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    // TODO if (o.generated) return;

    try genComment(o, writer);
    if (gen_obj_based_api) {
        try genNativeStruct(o, schema, imports, writer);
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

        try genStructAccessor(o, field, schema, imports, writer);
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
        try genStructBuilder(o, schema, imports, writer);
    } else {
        // Create a set of functions that allow table construction.
        try genTableBuilders(o, schema, imports, writer);
    }
    _ = try writer.write(
        \\};
        \\
        \\
    );
}

fn genKeyCompare(o: Object, _: Field, writer: anytype) !void {
    // const fname = fieldName(field.Name());
    // const fname_camel_upper = util.fmtCamelUpper(field.Name());
    try writer.print(
        \\pub fn KeyCompare(rcv: {s}) u32 {{
        \\_ = rcv;
        \\// TODO
        \\}}
        \\
        \\
    , .{lastName(o.Name())});
}

fn genLookupByKey(o: Object, _: Field, writer: anytype) !void {
    try writer.print(
        \\pub fn LookupByKey(rcv: {s}) u32 {{
        \\_ = rcv;
        \\// TODO
        \\}}
        \\
        \\
    , .{lastName(o.Name())});
}

pub fn generate(
    alloc: mem.Allocator,
    bfbs_path: []const u8,
    gen_path: []const u8,
    basename: []const u8,
    opts: anytype,
) !void {
    std.log.debug(
        "bfbs_path={s} gen_path={s} basename={s}",
        .{ bfbs_path, gen_path, basename },
    );
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const dirname_len = if (std.fs.path.dirname(basename)) |dirname|
        dirname.len + 1
    else
        0;
    const file_ident = try std.fmt.bufPrint(&buf, "//{s}.fbs", .{basename[dirname_len..]});
    std.log.debug("file_ident={s}", .{file_ident});
    const f = try std.fs.cwd().openFile(bfbs_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(alloc, std.math.maxInt(u16));
    defer alloc.free(content);
    const schema = Schema.GetRootAs(content, 0);
    // const writer = zig_file.writer();
    var needs_imports = false;
    var one_file_code = std.ArrayList(u8).init(alloc);
    const owriter = one_file_code.writer();
    var imports = TypenameSet.init(alloc);
    std.log.debug("schema.EnumsLen()={}", .{schema.EnumsLen()});
    for (0..schema.EnumsLen()) |i| {
        const e = schema.Enums(i).?;
        const decl_file = e.DeclarationFile();
        const same_file = decl_file.len == 0 or mem.eql(u8, decl_file, file_ident);
        std.log.debug("same_file={} decl_file={s}", .{ same_file, decl_file });
        if (!same_file) continue;

        var enumcode: std.ArrayListUnmanaged(u8) = .{};
        defer enumcode.deinit(alloc);
        const ewriter = enumcode.writer(alloc);
        imports.clearRetainingCapacity();
        try genEnum(e, schema, &imports, ewriter);
        if (e.IsUnion()) {
            try genNativeUnion(e, schema, &imports, ewriter);
            try genNativeUnionPack(e, ewriter);
            try genNativeUnionUnpack(e, schema, &imports, ewriter);
            _ = try ewriter.write("};\n\n");
        }

        if (opts.@"gen-onefile")
            _ = try owriter.write(enumcode.items)
        else {
            try imports.put(e.Name(), if (e.IsUnion()) .UNION else e.UnderlyingType().?.BaseType());
            try saveType(
                gen_path,
                bfbs_path,
                decl_file,
                basename,
                e.Name(),
                enumcode.items,
                needs_imports,
                imports,
                .enum_,
            );
        }
    }
    std.log.debug("schema.ObjectsLen()={}", .{schema.ObjectsLen()});
    for (0..schema.ObjectsLen()) |i| {
        const o = schema.Objects(i).?;
        const decl_file = o.DeclarationFile();
        const same_file = decl_file.len == 0 or mem.eql(u8, decl_file, file_ident);
        if (!same_file) continue;

        std.log.info("writing struct {s} {s}", .{ o.Name(), decl_file });
        var structcode: std.ArrayListUnmanaged(u8) = .{};
        defer structcode.deinit(alloc);
        const swriter = structcode.writer(alloc);
        imports.clearRetainingCapacity();
        try genStruct(o, schema, !opts.@"no-gen-object-api", &imports, swriter);

        if (opts.@"gen-onefile")
            _ = try owriter.write(structcode.items)
        else {
            try imports.put(o.Name(), .STRUCT);
            try saveType(
                gen_path,
                bfbs_path,
                decl_file,
                basename,
                o.Name(),
                structcode.items,
                needs_imports,
                imports,
                .struct_,
            );
        }
    }

    std.debug.print("{s}\n", .{one_file_code.items});
    // const zig_filename = try std.mem.concat(alloc, u8, &.{ basename, ".fb.zig" });
    // const zig_filepath = try std.fs.path.join(alloc, &.{ gen_path, zig_filename });
    // const zig_file = try std.fs.cwd().createFile(zig_filepath, .{});
    // defer zig_file.close();
}
