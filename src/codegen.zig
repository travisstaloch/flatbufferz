//!
//! this is a port of https://github.com/google/flatbuffers/blob/master/src/idl_gen_go.cpp
//!

const std = @import("std");
const mem = std.mem;
const Writer = std.io.Writer;
const fb = @import("flatbufferz");
const refl = fb.reflection;
const Schema = refl.Schema;
const Enum = refl.Enum;
const EnumVal = refl.EnumVal;
const Object = refl.Object;
const Field = refl.Field;
const Type = refl.Type;
const BaseType = refl.BaseType;
const util = fb.util;
const common = fb.common;
const todo = common.todo;
const getFieldIdxById = util.getFieldIdxById;
const TypenameSet = std.StringHashMap(BaseType);
const debug = false;

fn genComment(e: anytype, comment_type: enum { doc, normal }, writer: anytype) !void {
    const prefix = switch (comment_type) {
        .doc => "///",
        .normal => "//",
    };
    for (0..e.DocumentationLen()) |i| {
        if (e.Documentation(i)) |d| try writer.print("{s}{s}\n", .{ prefix, d });
    }
}

fn zigScalarTypename(base_type: BaseType) []const u8 {
    return switch (base_type) {
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
        .Vector, .Obj, .Union, .Array, .UType, .None => common.panicf("zigScalarTypename() unexpected type: {}", .{base_type}),
        .MaxBaseType => unreachable,
    };
}

pub const scalar_sizes = blk: {
    const tags = std.meta.tags(BaseType);
    var result: [tags.len]?u32 = undefined;
    for (tags, 0..) |tag, i| {
        result[i] = switch (tag) {
            .Bool => 1,
            .Byte => 1,
            .UByte => 1,
            .Short => 2,
            .UShort => 2,
            .Int => 4,
            .UInt => 4,
            .Long => 8,
            .ULong => 8,
            .Float => 4,
            .Double => 8,
            .String => 4, // defined as sizeof(Offset<void>) (== 4) in idl_gen_go.cpp
            else => null,
        };
    }
    break :blk result;
};

fn lastName(namespaced_name: []const u8) []const u8 {
    const last_dot = if (std.mem.lastIndexOfScalar(u8, namespaced_name, '.')) |i| i + 1 else 0;
    return namespaced_name[last_dot..];
}

pub fn firstName(namespaced_name: []const u8) []const u8 {
    const first_dot = if (std.mem.indexOfScalar(u8, namespaced_name, '.')) |i| i else namespaced_name.len;
    return namespaced_name[0..first_dot];
}

pub const CamelUpperFmt = struct {
    s: []const u8,
    imports: *const TypenameSet,
    prefix: []const u8 = "",
    suffix: []const u8 = "",

    pub fn format(v: CamelUpperFmt, writer: *Writer) Writer.Error!void {
        var buf: [std.fs.max_name_bytes]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const bufwriter = fbs.writer();
        _ = bufwriter.write(v.prefix) catch return error.WriteFailed;
        util.toCamelCase(v.s, true, bufwriter) catch return error.WriteFailed;
        _ = bufwriter.write(v.suffix) catch return error.WriteFailed;
        //
        // prevent namespace collisions by appending underscores
        //
        // if a field name matches an imported namespace, append '_' to the field name
        while (v.imports.contains(fbs.getWritten())) {
            bufwriter.writeByte('_') catch return error.WriteFailed;
        }
        // if a field has the same name as the first component of an imported namespace,
        // append '_' to the field name
        var iter = v.imports.iterator();
        while (true) {
            while (iter.next()) |e| {
                const first = firstName(e.key_ptr.*);
                if (mem.eql(u8, first, fbs.getWritten())) {
                    bufwriter.writeByte('_') catch return error.WriteFailed;
                    break;
                }
            } else break;
        }
        _ = try writer.write(fbs.getWritten());
    }

    pub fn withPrefix(f: CamelUpperFmt, prefix: []const u8) CamelUpperFmt {
        var r = f;
        r.prefix = prefix;
        return r;
    }

    pub fn withSuffix(f: CamelUpperFmt, suffix: []const u8) CamelUpperFmt {
        var r = f;
        r.suffix = suffix;
        return r;
    }
};

pub fn camelUpperFmt(s: []const u8, imports: *const TypenameSet) CamelUpperFmt {
    return .{ .s = s, .imports = imports };
}

const TypeFmt = struct {
    ty: Type,
    schema: Schema,
    mode: Mode,
    imports: *TypenameSet,
    opts: Opts,
    const Mode = enum { skip_ns, keep_ns };
    const Opts = struct { is_optional: bool = false };
    pub fn init(
        ty: Type,
        schema: Schema,
        mode: TypeFmt.Mode,
        imports: *TypenameSet,
        opts: Opts,
    ) TypeFmt {
        return .{
            .ty = ty,
            .schema = schema,
            .mode = mode,
            .imports = imports,
            .opts = opts,
        };
    }

    /// write a type name to writer. adds enum and struct names to `imports`
    /// mode:
    ///   .keep_ns: fully qualified
    ///   .skip_ns: only write the last name component
    pub fn format(tnf: TypeFmt, writer: *Writer) Writer.Error!void {
        const ty = tnf.ty;
        const schema = tnf.schema;
        const mode = tnf.mode;
        const imports = tnf.imports;
        const base_ty = ty.BaseType();
        if ((fb.idl.isScalar(base_ty) and ty.Index() != -1) or base_ty == .Union) {
            const e = schema.Enums(@as(u32, @bitCast(ty.Index()))).?;
            const name = switch (mode) {
                .keep_ns => e.Name(),
                .skip_ns => lastName(e.Name()),
            };
            imports.put(e.Name(), base_ty) catch return error.WriteFailed;
            if (tnf.opts.is_optional and fb.idl.isScalar(base_ty))
                try writer.writeByte('?');
            _ = try writer.write(name);
        } else if (fb.idl.isScalar(base_ty) or base_ty == .String) {
            if (tnf.opts.is_optional and base_ty != .String)
                try writer.writeByte('?');
            _ = try writer.write(zigScalarTypename(base_ty));
        } else if (fb.idl.isStruct(base_ty)) {
            const o = schema.Objects(@intCast(ty.Index())).?;
            const name = switch (mode) {
                .keep_ns => o.Name(),
                .skip_ns => lastName(o.Name()),
            };
            imports.put(o.Name(), base_ty) catch return error.WriteFailed;
            if (tnf.opts.is_optional and fb.idl.isScalar(base_ty))
                try writer.writeByte('?');
            _ = try writer.write(name);
        } else if (base_ty == .None) {
            _ = try writer.write("void");
        } else if (base_ty == .Vector) {
            const ele = ty.Element();
            if (fb.idl.isScalar(ele) or ele == .String)
                _ = try writer.write(zigScalarTypename(ele))
            else if (fb.idl.isStruct(ele)) {
                const o = schema.Objects(@intCast(ty.Index())).?;
                const name = switch (mode) {
                    .keep_ns => o.Name(),
                    .skip_ns => lastName(o.Name()),
                };
                imports.put(o.Name(), ele) catch return error.WriteFailed;
                _ = try writer.write(name);
            } else todo("TypeFmt.init() base_ty={} ele={}", .{ base_ty, ele });
        } else if (base_ty == .Array) {
            const ele = ty.Element();
            try writer.print("[{}]", .{ty.FixedLength()});
            if (fb.idl.isScalar(ele) or ele == .String)
                _ = try writer.write(zigScalarTypename(ele))
            else
                todo("TypeFmt.init() Array with non-scalar element={}", .{ele});
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
    try writer.print("pub const {f}", .{TypeFmt.init(
        e.UnderlyingType().?,
        schema,
        .skip_ns,
        imports,
        .{},
    )});
    if (fb.idl.isUnion(base_type) or base_type == .UType)
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
    const e = schema.Objects(@as(u32, @bitCast(idx))).?;
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
    try genComment(e, .doc, writer);
    const base_type = e.UnderlyingType().?.BaseType();
    try genEnumType(e, writer, schema, base_type, imports);
    {
        var i: u32 = 0;
        while (i < e.ValuesLen()) : (i += 1) {
            const ev = e.Values(i).?;
            try genComment(ev, .doc, writer);
            if (fb.idl.isUnion(base_type) or base_type == .UType)
                try unionMember(e, ev, schema, writer)
            else
                try enumMember(e, ev, writer);
        }
    }
    if (e.IsUnion())
        _ = try writer.write("\n\npub const Tag = std.meta.Tag(@This());\n");

    try writer.print(
        \\pub fn tagName(v: @This()) []const u8 {{
        \\return @tagName(v);
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
    try writer.print("pub const {s}T = union({s}.Tag) {{\n", .{ last_name, last_name });
    {
        var i: u32 = 0;
        while (i < e.ValuesLen()) : (i += 1) {
            const ev = e.Values(i).?;
            const utype = ev.UnionType().?;
            const base_ty = utype.BaseType();
            try writer.print("{s}: ", .{ev.Name()});
            if (base_ty == .Obj or base_ty == .Union) _ = try writer.write("?*");
            try writer.print("{f}", .{TypeFmt.init(
                utype,
                schema,
                .keep_ns,
                imports,
                .{},
            )});
            if (base_ty == .Obj or base_ty == .Union) _ = try writer.write("T");
            _ = try writer.write(",\n");
        }
    }
    try writer.print(
        \\
        \\pub fn deinit(self: *{s}T, allocator: std.mem.Allocator) void {{
        \\_ = .{{self, allocator}};
        \\switch (self.*) {{
        \\
    , .{last_name});
    {
        var i: u32 = 0;
        while (i < e.ValuesLen()) : (i += 1) {
            const ev = e.Values(i).?;
            const utype = ev.UnionType().?;
            const base_ty = utype.BaseType();
            const name = ev.Name();
            if (ev.Value() == 0)
                try writer.print(".{s} => {{}},\n", .{name})
            else if (base_ty == .Obj)
                try writer.print(
                    \\.{0s} => |mptr| if (mptr) |x| {{
                    \\x.deinit(allocator);
                    \\allocator.destroy(x);
                    \\self.{0s} = null;
                    \\}},
                    \\
                ,
                    .{name},
                );
        }
    }
    _ = try writer.write(
        \\}
        \\}
        \\
    );
}

/// gen a union pack() method
fn genNativeUnionPack(e: Enum, writer: anytype) !void {
    const ename = e.Name();
    const last_name = lastName(ename);
    try writer.print(
        \\
        \\pub fn Pack(rcv: {0s}T, __builder: *Builder, __pack_opts: fb.common.PackOptions) !u32 {{
        \\_ = .{{__builder, __pack_opts}};
        \\{1s}std.debug.print("pack() {0s}T rcv=.{{s}}\n", .{{@tagName(rcv)}});
        \\switch (rcv) {{
        \\
    ,
        .{ last_name, if (debug) "" else "// " },
    );

    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        if (ev.Value() == 0)
            try writer.print(".{s} => {{}},\n", .{ev.Name()})
        else
            try writer.print(".{s} => |x| return x.?.Pack(__builder, __pack_opts),\n", .{ev.Name()});
    }
    _ = try writer.write(
        \\}
        \\return 0;
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
        \\pub fn Unpack(rcv: {0s}.Tag, table: fb.Table, __pack_opts: fb.common.PackOptions) !{1s}T {{
        \\_ = .{{table, __pack_opts}};
        \\{2s}std.debug.print("unpack() {0s} rcv=.{{s}}\n", .{{@tagName(rcv)}});
        \\switch (rcv) {{
        \\
    ,
        .{ last_name, last_name, if (debug) "" else "// " },
    );
    var i: u32 = 0;
    while (i < e.ValuesLen()) : (i += 1) {
        const ev = e.Values(i).?;
        if (ev.Value() == 0)
            try writer.print(".{s} => return .{s},\n", .{ ev.Name(), ev.Name() })
        else {
            try writer.print(".{s} => {{\n", .{ev.Name()});

            const fty_fmt = TypeFmt.init(ev.UnionType().?, schema, .keep_ns, imports, .{});
            try writer.print(
                \\const x = {0f}.init(table.bytes, table.pos);
                \\const ptr = try __pack_opts.allocator.?.create({0f}T);
                \\ptr.* = try {0f}T.Unpack(x, __pack_opts);
                \\return .{{ .{1s} = ptr }};
                \\}},
                \\
            , .{ fty_fmt, ev.Name() });
        }
    }
    _ = try writer.write(
        \\}
        \\unreachable;
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
    schema: Schema,
) !void {
    if (contents.len == 0) return;

    _ = .{ needs_imports, kind };
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const outpath = try typenameToPath(&buf, gen_path, typename, ".fb.zig");
    std.fs.cwd().makePath(std.fs.path.dirname(outpath).?) catch |e| {
        std.log.err("couldn't make dir {?s}", .{std.fs.path.dirname(outpath)});
        return e;
    };

    // use std.zig.Ast to parse() and render() the generated source so that it
    // looks nice. this is equivalent to running 'zig fmt' on the file.
    const alloc = imports.allocator;

    var src = std.ArrayList(u8).init(alloc);
    defer src.deinit();
    var src_ad = src.writer().adaptToNewApi();
    try genPrelude(bfbs_path, decl_file, basename, typename, imports, schema, &src_ad.new_interface);
    try src_ad.new_interface.writeAll(contents);

    var ast = try std.zig.Ast.parse(alloc, try src.toOwnedSliceSentinel(0), .zig);
    defer ast.deinit(alloc);
    if (ast.errors.len > 0) {
        for (ast.errors) |err| {
            var errbuf = std.ArrayList(u8).init(alloc);
            defer errbuf.deinit();
            ast.renderError(err, errbuf.writer()) catch {};
            // TODO print a better error message. maybe try to
            // show the source which caused the error?
            std.log.err("formatting {s}: {s}", .{ typename, errbuf.items });
        }
        return error.InvalidGeneratedCode;
    }

    const formatted_src = try ast.render(alloc);
    defer alloc.free(formatted_src);

    const f = try std.fs.cwd().createFile(outpath, .{});
    defer f.close();
    try f.writeAll(formatted_src);
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
    var iter = mem.splitScalar(u8, a, '.');
    var pos: usize = 0;
    var mnext = iter.next();
    while (mnext) |it| : (pos += it.len) {
        if (!mem.eql(u8, it, b[pos..][0..it.len])) return pos;
        mnext = iter.next();
        pos += @intFromBool(mnext != null); // don't advance pos past the end of a
    }
    return pos;
}

const NsTmpArr = std.BoundedArray(u8, std.fs.max_name_bytes);

pub fn RepeatedFmt(comptime rep: []const u8, comptime sep: u8) type {
    return struct {
        times: usize,
        pub fn format(value: @This(), writer: *Writer) Writer.Error!void {
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
    depth: usize,
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
                    var buf: [@typeInfo(@TypeOf(path_buf.buffer)).array.len]u8 = undefined;
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

                    const dotsfmt = RepeatedFmt("..", std.fs.path.sep){ .times = dots };

                    try writer.print(
                        \\const {0s} = @import("{3f}{1s}{0s}{2s}").{0s};
                        \\
                    , .{ full_name, path, extension, dotsfmt });
                    if (base_ty == .Obj or base_ty == .UType)
                        try writer.print(
                            \\const {0s}T = @import("{3f}{1s}{0s}{2s}").{0s}T;
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
                        const dots_fmt = RepeatedFmt("..", std.fs.path.sep){ .times = dots };
                        try writer.print(
                            \\const {0s} = @import("{2f}{0s}{1s}").{0s};
                            \\
                        , .{ full_name, extension, dots_fmt });
                        if (base_ty == .Obj or base_ty == .UType)
                            try writer.print(
                                \\const {0s}T = @import("{2f}{0s}{1s}").{0s}T;
                                \\
                            , .{ full_name, extension, dots_fmt });
                    }
                }
            },
            .node => |map| {
                if (depth == 0)
                    _ = try writer.write("// a namespace generated by flatc-zig to match typenames produced by flatc\n");

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
    schema: Schema,
    writer: *Writer,
) !void {
    try writer.print(
        \\//!
        \\//! generated by flatc-zig
        \\//! binary:     {s}
        \\//! schema:     {s}.fbs
        \\//! file ident: {s}
        \\//! typename    {s}
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
    try writer.writeByte('\n');

    if (isRootTable(typename, schema))
        try writer.print(
            \\pub const __file_ident: fb.Builder.Fid = "{s}".*;
            \\pub const __file_ext = "{s}";
            \\
            \\
        , .{ schema.FileIdent(), schema.FileExt() });
}

fn isRootTable(typename: []const u8, schema: Schema) bool {
    return if (schema.RootTable()) |root_table|
        mem.eql(u8, typename, root_table.Name())
    else
        false;
}

// FIXME: unused
fn hasAttribute(x: anytype, key: []const u8) bool {
    var i: u32 = 0;
    while (i < x.AttributesLen()) : (i += 1) {
        const a = x.Attributes(i).?;
        if (mem.eql(u8, a.Key(), key)) return true;
    }
    return false;
}

fn isStruct(object_index: i32, schema: Schema) bool {
    const o = schema.Objects(@as(u32, @bitCast(object_index))).?;
    return o.IsStruct();
}

fn genNativeTablePack(o: Object, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    const oname = o.Name();
    const struct_type = lastName(oname);
    try writer.print(
        \\pub fn Pack(rcv: {s}T, __builder: *Builder, __pack_opts: fb.common.PackOptions) fb.common.PackError!u32 {{
        \\_ = .{{__pack_opts}};
        \\var __tmp_offsets = std.ArrayListUnmanaged(u32){{}};
        \\defer if(__pack_opts.allocator) |alloc| __tmp_offsets.deinit(alloc);
        \\
    , .{struct_type});
    {
        const fields_len = o.FieldsLen();
        if (fields_len == 0) _ = try writer.write("_ = rcv;\n");

        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(getFieldIdxById(o, i).?).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            if (fb.idl.isScalar(field_base_ty)) continue;
            const fname_orig = field.Name();
            if (mem.endsWith(u8, fname_orig, "_type") and field_base_ty == .UType)
                continue;
            const fname_off = FmtWithSuffix("_off"){ .name = fname_orig };
            if (field_base_ty == .String) {
                try writer.print(
                    \\const {0f} = if (rcv.{1f}.len != 0) try __builder.createString(rcv.{1f}) else 0;
                    \\
                , .{ fname_off, fieldNameFmt(fname_orig, imports) });
            } else if (fb.idl.isVector(field_base_ty) and
                field_ty.Element() == .UByte and
                !fb.idl.isUnion(field_base_ty))
            {
                if (field_ty.Index() == -1)
                    try writer.print(
                        \\const {0f} = if (rcv.{1f}.len != 0)
                        \\try __builder.createByteString(rcv.{1f})
                        \\else
                        \\0;
                        \\
                    , .{ fname_off, fieldNameFmt(fname_orig, imports) })
                else
                    try writer.print(
                        \\const {0f} = if (rcv.{1f}.items.len != 0)
                        \\try __builder.createByteString(rcv.{1f}.items)
                        \\else
                        \\0;
                        \\
                    , .{ fname_off, fieldNameFmt(fname_orig, imports) });
            } else if (fb.idl.isVector(field_base_ty)) {
                const fname_len = FmtWithSuffix("_len"){ .name = fname_orig };
                try writer.print(
                    \\var {0f}: u32 = 0;
                    \\if (rcv.{1f}.items.len != 0) {{
                    \\const {2f}: i32 = @intCast(rcv.{1f}.items.len);
                    \\
                , .{ fname_off, fieldNameFmt(fname_orig, imports), fname_len });
                const fty_ele = field_ty.Element();
                if (fty_ele == .String) {
                    try writer.print(
                        \\try __tmp_offsets.ensureTotalCapacity(__pack_opts.allocator.?, @as(u32, @bitCast({0f})));
                        \\__tmp_offsets.items.len = @as(u32, @bitCast({0f}));
                        \\for (__tmp_offsets.items, 0..) |*off, j| {{
                        \\off.* = try __builder.createString(rcv.{1f}.items[j]);
                        \\}}
                        \\
                    , .{ fname_len, fieldNameFmt(fname_orig, imports) });
                } else if (fty_ele == .Obj and !isStruct(field_ty.Index(), schema)) {
                    const fty_fmt = TypeFmt.init(
                        field_ty,
                        schema,
                        .keep_ns,
                        imports,
                        .{ .is_optional = field.Optional() },
                    );
                    try writer.print(
                        \\try __tmp_offsets.ensureTotalCapacity(__pack_opts.allocator.?, @as(u32, @bitCast({0f})));
                        \\__tmp_offsets.items.len = @as(u32, @bitCast({0f}));
                        \\for (__tmp_offsets.items, 0..) |*off, j| {{
                        \\off.* = try {2f}T.Pack(rcv.{1f}.items[j], __builder, __pack_opts);
                        \\}}
                        \\
                    , .{ fname_len, fieldNameFmt(fname_orig, imports), fty_fmt });
                }

                const fname_camel_upper = camelUpperFmt(fname_orig, imports);
                try writer.print(
                    \\_ = try {s}.Start{f}Vector(__builder, {2f});
                    \\{{
                    \\var j = {2f} - 1;
                    \\while (j >= 0) : (j -= 1) {{
                    \\
                , .{ struct_type, fname_camel_upper, fname_len });
                if (fb.idl.isScalar(fty_ele)) {
                    try writer.print(
                        "try __builder.prepend({s}, rcv.{f}.items[@as(u32, @bitCast(j))]);\n",
                        .{ zigScalarTypename(fty_ele), fieldNameFmt(fname_orig, imports) },
                    );
                } else if (fty_ele == .Obj and isStruct(field_ty.Index(), schema)) {
                    try writer.print("_ = try rcv.{s}.items[@as(u32, @bitCast(j))].Pack(__builder, __pack_opts);\n", .{fname_orig});
                } else {
                    try writer.print("try __builder.prependUOff(__tmp_offsets.items[@as(u32, @bitCast(j))]);", .{});
                }
                try writer.print(
                    \\}}
                    \\{0f} = try __builder.endVector(@bitCast({1f}));
                    \\}}
                    \\}}
                    \\
                , .{ fname_off, fname_len });
            } else if (field_base_ty == .Obj) {
                if (isStruct(field_ty.Index(), schema)) continue;
                try writer.print(
                    \\const {0f} = if (rcv.{1f}) |x| try x.Pack(__builder, __pack_opts) else 0;
                    \\
                ,
                    .{ fname_off, fieldNameFmt(fname_orig, imports) },
                );
            } else if (field_base_ty == .Union) {
                try writer.print(
                    "const {0f} = try rcv.{1f}.Pack(__builder, __pack_opts);\n",
                    .{ fname_off, fieldNameFmt(fname_orig, imports) },
                );
            } else unreachable;
            try writer.writeByte('\n');
        }
    }

    try writer.print("try {s}.Start(__builder);\n", .{struct_type});

    {
        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(getFieldIdxById(o, i).?).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            const fname_orig = field.Name();
            if (mem.endsWith(u8, fname_orig, "_type") and field_base_ty == .UType)
                continue;
            const fname_off = FmtWithSuffix("_off"){ .name = fname_orig };
            const fname_camel_upper = camelUpperFmt(fname_orig, imports).withPrefix("Add");
            if (fb.idl.isScalar(field_base_ty)) {
                if (field_base_ty != .Union) {
                    if (field.Optional())
                        try writer.print(
                            \\if (rcv.{2f}) |x| try {0s}.{1f}(__builder, x);
                            \\
                        ,
                            .{ struct_type, fname_camel_upper, fieldNameFmt(fname_orig, imports) },
                        )
                    else
                        try writer.print(
                            "try {s}.{f}(__builder, rcv.{f});\n",
                            .{ struct_type, fname_camel_upper, fieldNameFmt(fname_orig, imports) },
                        );
                }
            } else {
                if (field_base_ty == .Obj and isStruct(field_ty.Index(), schema)) {
                    try writer.print(
                        "const {0f} = if (rcv.{1f}) |x| try x.Pack(__builder, __pack_opts) else 0;\n",
                        .{ fname_off, fieldNameFmt(fname_orig, imports) },
                    );
                } else if (field_base_ty == .Union) {
                    try writer.print(
                        \\try {0s}.{1f}Type(__builder, rcv.{2f});
                        \\
                    ,
                        .{ struct_type, fname_camel_upper, fieldNameFmt(fname_orig, imports) },
                    );
                }
                try writer.print(
                    "try {s}.{f}(__builder, {f});\n",
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
        \\pub fn UnpackTo(rcv: {s}, t: *{s}T, __pack_opts: fb.common.PackOptions) !void {{
        \\_ = .{{__pack_opts}};
        \\
    ,
        .{ struct_type, struct_type },
    );
    {
        const fields_len = o.FieldsLen();
        if (fields_len == 0) _ = try writer.write("_ = rcv;\n_ = t;\n");

        var i: u32 = 0;
        while (i < o.FieldsLen()) : (i += 1) {
            const field = o.Fields(getFieldIdxById(o, i).?).?;
            if (field.Deprecated()) continue;
            const field_ty = field.Type().?;
            const field_base_ty = field_ty.BaseType();
            const fname = fieldNameFmt(field.Name(), imports);
            const fname_upper_camel = camelUpperFmt(field.Name(), imports);
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
            if (mem.endsWith(u8, fname.fname, "_type") and field_base_ty == .UType)
                continue;
            const fty_fmt = TypeFmt.init(
                field_ty,
                schema,
                .keep_ns,
                imports,
                .{ .is_optional = field.Optional() },
            );
            if ((fb.idl.isScalar(field_base_ty) or field_base_ty == .String) and
                field_base_ty != .Union)
            {
                try writer.print(
                    "t.{f} = rcv.{f}();\n",
                    .{ fname, fname_upper_camel },
                );
            } else if (field_base_ty == .Vector and
                field_ty.Element() == .UByte and
                field_ty.Index() == -1)
            {
                try writer.print(
                    \\t.{f} = rcv.{f}Bytes();
                    \\
                ,
                    .{ fname, fname_upper_camel },
                );
            } else if (field_base_ty == .Vector) {
                const fname_len = FmtWithSuffix("_len"){ .name = field.Name() };
                const ele = field_ty.Element();
                if (ele == .Obj)
                    try writer.print(
                        \\const {3f} = rcv.{1f}();
                        \\t.{0f} = try std.ArrayListUnmanaged({2f}T).initCapacity(__pack_opts.allocator.?, @as(u32, @bitCast({3f})));
                        \\t.{0f}.expandToCapacity();
                        \\{{
                        \\var j: u32 = 0;
                        \\while (j < {3f}) : (j += 1) {{
                        \\const x = rcv.{4f}(j).?;
                        \\
                    , .{ fname, fname_upper_camel.withSuffix("Len"), fty_fmt, fname_len, fname_upper_camel })
                else
                    try writer.print(
                        \\const {3f} = rcv.{1f}();
                        \\t.{0f} = try std.ArrayListUnmanaged({2f}).initCapacity(__pack_opts.allocator.?, @as(u32, @bitCast({3f})));
                        \\t.{0f}.expandToCapacity();
                        \\{{
                        \\var j: u32 = 0;
                        \\while (j < {3f}) : (j += 1) {{
                        \\
                    , .{ fname, fname_upper_camel.withSuffix("Len"), fty_fmt, fname_len });

                try writer.print("t.{f}.items[j] = ", .{fname});
                const fty_ele = field_ty.Element();
                if (fb.idl.isScalar(fty_ele) or fty_ele == .String) {
                    try writer.print("rcv.{f}(j).?", .{fname_upper_camel});
                } else if (fty_ele == .Obj) {
                    try writer.print("try x.Unpack(__pack_opts)", .{});
                } else {
                    // TODO(iceboy): Support vector of unions.
                    unreachable;
                }
                _ = try writer.write(
                    \\;
                    \\}
                    \\}
                    \\
                );
            } else if (field_base_ty == .Obj) {
                try writer.print(
                    \\if (rcv.{0f}()) |x| {{
                    \\if (t.{2f} == null) {{
                    \\t.{2f} = try __pack_opts.allocator.?.create({1f}T);
                    \\t.{2f}.?.* = .{{}};
                    \\}}
                    \\try {1f}T.UnpackTo(x, t.{2f}.?, __pack_opts);
                    \\}}
                    \\
                , .{ fname_upper_camel, fty_fmt, fname });
            } else if (field_base_ty == .Union) {
                try writer.print(
                    \\if (rcv.{1f}()) |_tab| {{
                    \\t.{0f} = try {2f}T.Unpack(rcv.{3f}(), _tab, __pack_opts);
                    \\}}
                    \\
                , .{ fname, fname_upper_camel, fty_fmt, fname_upper_camel.withSuffix("Type") });
            } else unreachable;
            try writer.writeByte('\n');
        }
    }

    _ = try writer.write("}\n\n");
    try writer.print(
        \\pub fn Unpack(rcv: {0s}, __pack_opts: fb.common.PackOptions) fb.common.PackError!{0s}T {{
        \\var t = {0s}T{{}};
        \\try {0s}T.UnpackTo(rcv, &t, __pack_opts);
        \\return t;
        \\}}
        \\
        \\
    , .{struct_type});
}

fn genNativeStructPack(
    o: Object,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const olastname = lastName(o.Name());
    try writer.print(
        \\pub fn Pack(rcv: {0s}T, __builder: *Builder, __pack_opts: fb.common.PackOptions) !u32 {{
        \\_ = .{{__pack_opts}};
        \\return {0s}.Create(__builder
    , .{olastname});

    var nameprefix = NamePrefix{};
    try structPackArgs(o, &nameprefix, schema, imports, writer);
    _ = try writer.write(
        \\);
        \\}
        \\
    );
}

fn structPackArgs(
    o: Object,
    nameprefix: *NamePrefix,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(getFieldIdxById(o, i).?).?;
        const field_ty = field.Type().?;
        if (field_ty.BaseType() == .Obj) {
            const o2 = schema.Objects(@as(u32, @bitCast(field_ty.Index()))).?;
            const len = nameprefix.len;
            defer nameprefix.len = len;
            try nameprefix.appendSlice(field.Name());
            try nameprefix.appendSlice(".?.");
            try structPackArgs(o2, nameprefix, schema, imports, writer);
        } else try writer.print(", rcv.{s}{s}", .{ nameprefix.constSlice(), field.Name() });
    }
}

fn genNativeStructUnpack(o: Object, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    const olastname = lastName(o.Name());
    try writer.print(
        \\pub fn UnpackTo(rcv: {0s}, t: *{0s}T, __pack_opts: fb.common.PackOptions) !void {{
        \\_ = .{{__pack_opts}};
        \\
    , .{olastname});
    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(getFieldIdxById(o, i).?).?;
        const field_ty = field.Type().?;
        const fname = fieldNameFmt(field.Name(), imports);
        const fname_camel_upper = camelUpperFmt(field.Name(), imports);

        if (field_ty.BaseType() == .Obj) {
            const fty_fmt = TypeFmt.init(
                field_ty,
                schema,
                .keep_ns,
                imports,
                .{ .is_optional = field.Optional() },
            );
            try writer.print(
                \\if (t.{0f} == null) {{ 
                \\t.{0f} = try __pack_opts.allocator.?.create({1f}T);
                \\t.{0f}.?.* = .{{}};
                \\}}
                \\t.{0f}.?.* = try {1f}T.Unpack(rcv.{2f}(), __pack_opts);
                \\
            , .{ fname, fty_fmt, fname_camel_upper });
        } else try writer.print(
            "t.{f} = rcv.{f}();\n",
            .{ fname, fname_camel_upper },
        );
    }

    try writer.print(
        \\}}
        \\
        \\pub fn Unpack(rcv: {0s}, __pack_opts: fb.common.PackOptions) !{0s}T {{
        \\var t = {0s}T{{}};
        \\try {0s}T.UnpackTo(rcv, &t, __pack_opts);
        \\return t;
        \\}}
        \\
        \\
    , .{olastname});
}

fn genNativeDeinit(o: Object, _: Schema, imports: *TypenameSet, writer: anytype) !void {
    try writer.print(
        \\pub fn deinit(self: *{s}T, allocator: std.mem.Allocator) void {{
        \\_ = .{{self, allocator}}; 
        \\
    , .{lastName(o.Name())});

    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(getFieldIdxById(o, i).?).?;
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        const fname = fieldNameFmt(field.Name(), imports);

        switch (field_base_ty) {
            .String => {
                // TODO __pack_opts.dupe_strings - allow user to choose wether
                // to dupe and free strings using __pack_opts.allocator
                try writer.print(
                    \\// TODO __pack_opts.dupe_strings
                    \\// if(self.{0f}.len > 0) allocator.free(self.{0f});
                    \\
                , .{fname});
            },
            .Obj => {
                try writer.print(
                    \\if (self.{0f}) |x| {{
                    \\x.deinit(allocator);
                    \\allocator.destroy(x);
                    \\}}
                    \\
                , .{fname});
            },
            .Vector => {
                const ele = field_ty.Element();
                if (ele == .String)
                    try writer.print(
                        \\// TODO __pack_opts.dupe_strings
                        \\//for (self.{0f}.items) |it| {{
                        \\//_ = it;
                        \\//allocator.free(it);
                        \\//}}
                        \\
                    , .{fname})
                else if (!fb.idl.isScalar(ele))
                    try writer.print(
                        \\for (self.{0f}.items) |*it| it.deinit(allocator);
                        \\
                    , .{fname});
                if (ele == .UByte and field_ty.Index() == -1)
                    try writer.print(
                        \\// TODO __pack_opts.dupe_strings
                        \\// allocator.free(self.{0f});
                        \\
                    , .{fname})
                else
                    try writer.print(
                        \\self.{0f}.deinit(allocator);
                        \\
                    , .{fname});
            },
            .Union => {
                try writer.print(
                    \\self.{0f}.deinit(allocator);
                    \\
                , .{fname});
            },
            else => {},
        }
    }
    _ = try writer.write(
        \\}
        \\
    );
}

fn genNativeStruct(o: Object, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    const oname = o.Name();
    const last_name = lastName(oname);

    try writer.print("pub const {s}T = struct {{\n", .{last_name});

    var i: u32 = 0;
    while (i < o.FieldsLen()) : (i += 1) {
        const field = o.Fields(getFieldIdxById(o, i).?).?;
        if (field.Deprecated()) continue;
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        if (fb.idl.isScalar(field_base_ty) and field_base_ty == .Union) continue;
        const fname = field.Name();
        if (field_base_ty == .UType and mem.endsWith(u8, fname, "_type")) continue;

        try genComment(field, .doc, writer);
        try writer.print("{f}: ", .{fieldNameFmt(fname, imports)});
        const fty_fmt = TypeFmt.init(
            field_ty,
            schema,
            .keep_ns,
            imports,
            .{ .is_optional = field.Optional() },
        );
        if (fb.idl.isVector(field_base_ty)) {
            const ele = field_ty.Element();
            if (ele == .UByte and field_ty.Index() == -1) {
                _ = try writer.write(
                    \\[]const u8 = ""
                );
            } else {
                try writer.print("std.ArrayListUnmanaged({f}", .{fty_fmt});
                if (ele == .Obj or ele == .Union) _ = try writer.write("T");
                _ = try writer.write(") = .{}");
            }
        } else {
            // gen field type
            if (field_base_ty == .Obj) _ = try writer.write("?*");
            try writer.print("{f}", .{fty_fmt});
            if (field_base_ty == .Obj or field_base_ty == .Union)
                _ = try writer.write("T");
            // gen field default value
            if (field_base_ty == .Obj)
                _ = try writer.write(" = null")
            else if (field_base_ty == .Union) {
                try writer.print(" = @as({f}.Tag, @enumFromInt(0))", .{fty_fmt});
            } else if (field_base_ty == .String) {
                _ = try writer.write(" = \"\"");
            } else {
                _ = try writer.write(" = ");
                const field_ty_idx = field_ty.Index();
                if (field_ty_idx == -1)
                    try genConstant(field, field_base_ty, schema, imports, writer)
                else { // this is an enum type. use DefaultInteger() if non-zero
                    if (field.DefaultInteger() != 0)
                        try writer.print(
                            "@as({f}, @enumFromInt({}))",
                            .{ fty_fmt, field.DefaultInteger() },
                        )
                    else {
                        // DefaultInteger() == 0.
                        //   if field optional: null // FIXME: not sure this is correct
                        //   else: use first declared enum value
                        //   else: undefined
                        const enum_ty = schema.Enums(@as(u32, @bitCast(field_ty_idx))).?;
                        if (field.Optional())
                            _ = try writer.write("null")
                        else if (enum_ty.Values(0)) |ev|
                            try writer.print(
                                "@as({f}, @enumFromInt({}))",
                                .{ fty_fmt, ev.Value() },
                            )
                        else
                            _ = try writer.write("undefined");
                    }
                }
            }
        }
        _ = try writer.write(",\n");
    }
    try writer.writeByte('\n');
    if (!o.IsStruct()) {
        try genNativeTablePack(o, schema, imports, writer);
        try genNativeTableUnpack(o, schema, imports, writer);
    } else {
        try genNativeStructPack(o, schema, imports, writer);
        try genNativeStructUnpack(o, schema, imports, writer);
    }
    try genNativeDeinit(o, schema, imports, writer);
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
        \\pub fn GetRootAs(buf: []u8, offset: u32) {0s} {{
        \\const n = fb.encode.read(u32, buf[offset..]);
        \\return {0s}.init(buf, n+offset);
        \\}}
        \\
        \\
    , .{o.Name()});
    try writer.print(
        \\pub fn GetSizePrefixedRootAs(buf: []u8, offset: u32) {0s} {{
        \\const n = fb.encode.read(u32, buf[offset + fb.Builder.size_u32..]);
        \\return {0s}.init(buf, n+offset + fb.Builder.size_u32);
        \\}}
        \\
        \\
    , .{o.Name()});
}

fn initializeExisting(o: Object, writer: anytype) !void {
    // Initialize an existing object with other data, to avoid an allocation.
    if (o.IsStruct())
        try writer.print(
            \\pub fn init(bytes: []u8, pos: u32) {s} {{
            \\return .{{ ._tab = .{{ ._tab = .{{ .bytes = bytes, .pos = pos }}}}}};
            \\}}
            \\
            \\
        , .{lastName(o.Name())})
    else
        try writer.print(
            \\pub fn init(bytes: []u8, pos: u32) {s} {{
            \\return .{{ ._tab = .{{ .bytes = bytes, .pos = pos }}}};
            \\}}
            \\
            \\
        , .{lastName(o.Name())});
}

fn genTableAccessor(o: Object, writer: anytype) !void {
    // Initialize an existing object with other data, to avoid an allocation.
    if (o.IsStruct())
        try writer.print(
            \\pub fn Table(x: {s}) fb.Table {{
            \\return x._tab._tab;
            \\}}
            \\
            \\
        , .{lastName(o.Name())})
    else
        try writer.print(
            \\pub fn Table(x: {s}) fb.Table {{
            \\return x._tab;
            \\}}
            \\
            \\
        , .{lastName(o.Name())});
}

/// Get the length of a vector.
fn getVectorLen(o: Object, field: Field, imports: *TypenameSet, writer: anytype) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    try writer.print(
        \\pub fn {f}(rcv: {s}) u32 
    , .{ fname_camel_upper.withSuffix("Len"), lastName(o.Name()) });
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
fn getUByteSlice(
    o: Object,
    field: Field,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    try writer.print(
        \\pub fn {f}Bytes(rcv: {s}) []const u8
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
        .String => _ = try writer.write("rcv._tab.byteVector("),
        .Union => _ = try writer.write("rcv._tab.union_("),
        .Vector => switch (ty.Element()) {
            .String => _ = try writer.write("rcv._tab.byteVector("),
            .Union => _ = try writer.write("rcv._tab.union_("),
            .Vector => todo(".Vector .Vector", .{}),
            .Obj => todo(".Vector .Obj", .{}),
            else => |ele| {
                _ = try writer.write("rcv._tab.read(");
                if (fb.idl.isScalar(ele) or ele == .String) {
                    _ = try writer.write(zigScalarTypename(ele));
                    _ = try writer.write(", ");
                } else todo("genGetter .Vector {}", .{ele});
            },
        },
        else => |base_ty| {
            try writer.print(
                "rcv._tab.read({f}",
                .{TypeFmt.init(ty, schema, .keep_ns, imports, .{})},
            );
            if (fb.idl.isUnion(base_ty) or base_ty == .UType)
                _ = try writer.write(".Tag");
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
    return fb.idl.isScalar(field_base_ty) and field.Optional();
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
        .Bool => {
            const default = field.DefaultInteger() != 0;

            try writer.print("{}", .{default});
        },
        .Float => {
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
        .Double => {
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
        // FIXME: not sure about these values, just copied go ouptut
        .Obj, .Vector => _ = try writer.write("0"),
        else => {
            const field_ty = field.Type().?;
            const fty_fmt = TypeFmt.init(
                field_ty,
                schema,
                .keep_ns,
                imports,
                .{ .is_optional = field.Optional() },
            );
            // FIXME: clean this up. seems like it should be same logic as genConstant()
            if (field_ty.Index() == -1)
                try writer.print("{}", .{field.DefaultInteger()})
            else if (field_base_ty == .UType) {
                try writer.print("@as({f}.Tag, @enumFromInt({}))", .{
                    fty_fmt,
                    field.DefaultInteger(),
                });
            } else if (fb.idl.isInteger(field_base_ty)) {
                if (field.DefaultInteger() != 0)
                    try writer.print("@as({f}, @enumFromInt({}))", .{
                        fty_fmt,
                        field.DefaultInteger(),
                    })
                else {
                    const enum_ty = schema.Enums(@as(u32, @bitCast(field_ty.Index()))).?;
                    const ev = enum_ty.Values(0).?;
                    try writer.print("@as({f}, @enumFromInt({}))", .{
                        fty_fmt,
                        ev.Value(),
                    });
                }
            } else {
                try writer.print("{}\n", .{field.DefaultInteger()});
            }
        },
    }
}

const NamePrefix = std.BoundedArray(u8, std.fs.max_name_bytes);

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
        const field = o.Fields(getFieldIdxById(o, i).?).?;
        const field_ty = field.Type().?;
        const field_base_ty = field_ty.BaseType();
        if (field_base_ty == .Obj and isStruct(field_ty.Index(), schema)) {
            // Generate arguments for a struct inside a struct. To ensure names
            // don't clash, and to make it obvious these arguments are constructing
            // a nested struct, prefix the name with the field name.
            const o2 = schema.Objects(@as(u32, @bitCast(field_ty.Index()))).?;
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
            const fname = fieldNameFmt(field.Name(), imports);
            var argname = std.ArrayList(u8).init(alloc);
            try argname.appendSlice(nameprefix.constSlice());
            try argname.appendSlice(fname.fname);

            while (true) {
                const gop = try arg_names.getOrPut(alloc, argname.items);
                if (gop.found_existing)
                    try argname.append('_')
                else
                    break;
            }
            try writer.print(
                \\, {s}: {f}
            , .{
                argname.items,
                TypeFmt.init(
                    field_ty,
                    schema,
                    .keep_ns,
                    imports,
                    .{ .is_optional = field.Optional() },
                ),
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
    if (fb.idl.isScalar(field_ty.BaseType())) {
        try writer.print(
            "({f}",
            .{TypeFmt.init(
                field_ty,
                schema,
                .keep_ns,
                imports,
                .{ .is_optional = field.Optional() },
            )},
        );
        const field_base_ty = field_ty.BaseType();
        if (fb.idl.isUnion(field_base_ty) or field_base_ty == .UType)
            _ = try writer.write(".Tag");
        _ = try writer.write(", ");
    } else _ = try writer.write(if (field_ty.BaseType() == .Obj and
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

    var i = @as(i32, @intCast(o.FieldsLen())) - 1;
    while (i >= 0) : (i -= 1) {
        const field = o.Fields(getFieldIdxById(o, @intCast(i)).?).?;
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
        if (field_base_ty == .Obj and isStruct(field_ty.Index(), schema)) {
            const o2 = schema.Objects(@as(u32, @bitCast(field_ty.Index()))).?;
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
        const field = o.Fields(getFieldIdxById(o, i).?).?;
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
        if (field.Type().?.BaseType() == .Vector)
            try buildVectorOfTable(o, field, schema, imports, writer);
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    try writer.print(
        \\pub fn {f}(rcv: {s}) {f} {{
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    const field_base_ty = field_ty.BaseType();
    if (debug) try writer.print(
        "// base_ty={} isScalar()={} is_optional={} ty.Index()={} \n",
        .{ field_base_ty, fb.idl.isScalar(field_base_ty), field.Optional(), field_ty.Index() },
    );
    try writer.print(
        \\pub fn {f}(rcv: {s}) {f}
    , .{ fname_camel_upper, lastName(o.Name()), fty_fmt });
    if (fb.idl.isUnion(field_base_ty) or field_base_ty == .UType)
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const oname = o.Name();
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    try writer.print(
        \\pub fn {f}(rcv: {s}) {f}
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const oname = o.Name();
    const fty_fmt = TypeFmt.init(
        field.Type().?,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    try writer.print(
        \\pub fn {0f}(rcv: {1s}) {2f} {{
        \\return {2f}.init(rcv._tab._tab.bytes, rcv._tab._tab.pos + {3});
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const oname = o.Name();
    // Get the value of a union from an object.
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    try writer.print(
        \\pub fn {f}(rcv: {s}) ?{f}
    , .{ fname_camel_upper, lastName(oname), fty_fmt });
    try offsetPrefix(field, writer);
    const field_base_ty = field_ty.BaseType();
    if (field_base_ty == .Obj and isStruct(field_ty.Index(), schema))
        _ = try writer.write("const x = o + rcv._tab.pos;\n")
    else
        _ = try writer.write("const x = rcv._tab.indirect(o + rcv._tab.pos);\n");

    try writer.print(
        \\return {f}.init(rcv._tab.bytes, x);
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const oname = o.Name();

    // Get the value of a union from an object.
    try writer.print(
        \\pub fn {f}(rcv: {s}) ?fb.Table
    , .{ fname_camel_upper, lastName(oname) });
    try writer.writeByte('\n');
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

fn inlineSize(ty: Type, _: Schema) u32 {
    const base_ty = ty.BaseType();
    return switch (base_ty) {
        .Vector => if (scalar_sizes[@as(u8, @bitCast(@intFromEnum(ty.Element())))]) |scalar_size|
            scalar_size
        else switch (ty.Element()) {
            .Obj => blk: {
                break :blk @bitCast(ty.ElementSize());
            },
            .Vector => unreachable,
            .Union => unreachable,
            .Array => unreachable,
            .UType => unreachable,
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const oname = o.Name();
    const o2 = schema.Objects(@as(u32, @bitCast(field_ty.Index()))).?;
    try writer.print(
        \\pub fn {f}(rcv: {s}, j: usize) ?{s} 
    , .{ fname_camel_upper, lastName(oname), o2.Name() });
    try offsetPrefix(field, writer);
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    const indir_str = if (o2.IsStruct()) "" else "\nx = rcv._tab.indirect(x);";
    if (debug) try writer.print(
        \\// base={f} ele={f} fixed_len={f} base_size={f} ele_size={f}
        \\
    , .{
        field_ty.BaseType(),
        field_ty.Element(),
        field_ty.FixedLength(),
        field_ty.BaseSize(),
        field_ty.ElementSize(),
    });
    try writer.print(
        \\var x = rcv._tab.vector(o);
        \\x += @as(u32, @intCast(j)) * {0};{2s}
        \\return {1f}.init(rcv._tab.bytes, x);
        \\}}
        \\return null;
        \\}}
        \\
        \\
    , .{
        inlineSize(field_ty, schema),
        fty_fmt,
        indir_str,
    });
}

fn getMemberOfVectorOfStructByKey(
    o: Object,
    field: Field,
    key_field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const olastname = lastName(o.Name());
    const ty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    const keyty_fmt = TypeFmt.init(
        key_field.Type().?,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = key_field.Optional() },
    );

    try writer.print(
        \\pub fn {0f}ByKey(rcv: {1s}, obj: *{2f}, key: {3f}) bool 
    , .{ fname_camel_upper, olastname, ty_fmt, keyty_fmt });
    try offsetPrefix(field, writer);
    try writer.print(
        \\const x = rcv._tab.vector(o);
        \\return obj.LookupByKey(key, x, rcv._tab.bytes);
        \\}}
        \\return false;
        \\}}
        \\
        \\
    , .{});
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
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const oname = o.Name();

    try writer.print(
        \\pub fn {f}(rcv: {s}, j: usize) ?{f} 
    , .{
        fname_camel_upper,
        lastName(oname),
        TypeFmt.init(
            field_ty,
            schema,
            .keep_ns,
            imports,
            .{ .is_optional = field.Optional() },
        ),
    });

    _ = try writer.write(" ");

    try offsetPrefix(field, writer);
    _ = try writer.write(
        \\const a = rcv._tab.vector(o);
        \\return 
    );

    try genGetter(field_ty, schema, imports, writer);
    if (field_ty.BaseType() == .Vector and field_ty.Element() == .Obj and
        isStruct(field_ty.Index(), schema))
        try writer.print(
            \\rcv._tab.bytes, a + @as(u32, @intCast(j)) * {});
            \\}}
            \\
        , .{inlineSize(field_ty, schema)})
    else
        try writer.print(
            \\a + @as(u32, @intCast(j)) * {});
            \\}}
            \\
        , .{inlineSize(field_ty, schema)});
    const ele_basety = field_ty.Element();
    _ = try writer.write(if (ele_basety == .String)
        \\return "";
        \\
    else if (ele_basety == .Bool)
        \\return false;
        \\
    else if (field_ty.BaseType() == .Vector and field_ty.Element() == .Obj)
        \\return null;
        \\
    else
        \\return 0;
        \\
    );
    _ = try writer.write("}\n\n");
}

const FieldNameFmt = struct {
    fname: []const u8,
    imports: *const TypenameSet,

    pub fn format(self: @This(), writer: *Writer) Writer.Error!void {
        if (std.zig.Token.getKeyword(self.fname) != null or
            std.zig.primitives.isPrimitive(self.fname) or
            self.imports.contains(self.fname))
            try writer.print(
                \\@"{s}"
            , .{self.fname})
        else
            _ = try writer.write(self.fname);
    }
};
fn fieldNameFmt(fname: []const u8, imports: *const TypenameSet) FieldNameFmt {
    return .{ .fname = fname, .imports = imports };
}

fn FmtWithSuffix(comptime suffix: []const u8) type {
    return struct {
        name: []const u8,
        pub fn format(value: @This(), writer: *Writer) Writer.Error!void {
            var buf: [std.fs.max_name_bytes]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            const bufwriter = fbs.writer();
            _ = bufwriter.write(value.name) catch return error.WriteFailed;
            _ = bufwriter.write(suffix) catch return error.WriteFailed;
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
    const fname = fieldNameFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_base_ty = field_ty.BaseType();

    if (debug) try writer.print(
        \\//fname={f} field_base_ty={f}
        \\
    , .{ fname, field_base_ty });

    try writer.print(
        \\pub fn {f}(__builder: *Builder, {f}: 
    , .{ fname_camel_upper.withPrefix("Add"), fname });

    const fty_fmt = TypeFmt.init(field_ty, schema, .keep_ns, imports, .{});
    if (!fb.idl.isScalar(field_base_ty) and !o.IsStruct()) {
        _ = try writer.write("u32");
    } else if (fb.idl.isUnion(field_base_ty) or field_base_ty == .UType) {
        try writer.print("{f}.Tag", .{fty_fmt});
    } else {
        try writer.print("{f}", .{fty_fmt});
    }

    _ = try writer.write(
        \\) !void {
        \\try __builder.prepend
    );
    if (isScalarOptional(field, field_base_ty)) {
        try writer.print("({f}, ", .{fty_fmt});
    } else {
        _ = try writer.write("Slot");
        try genMethod(field, schema, imports, writer);
        try writer.print("{}, ", .{offset});
    }

    try writer.print("{f}", .{fname});

    if (isScalarOptional(field, field_base_ty)) {
        try writer.print(
            \\);
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
fn buildVectorOfTable(_: Object, field: Field, schema: Schema, imports: *TypenameSet, writer: anytype) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const ele = field_ty.Element();
    const alignment = if (fb.idl.isScalar(ele) or ele == .String)
        scalar_sizes[@as(u8, @bitCast(@intFromEnum(ele)))].?
    else switch (ele) {
        .Obj => blk: {
            const o2 = schema.Objects(@as(u32, @bitCast(field_ty.Index()))).?;
            const minalign = o2.Minalign();
            break :blk if (minalign == -1)
                todo("alignment .Obj minalign == -1 ", .{})
            else
                @as(u32, @bitCast(minalign));
        },
        .None,
        .Vector,
        .Union,
        .Array,
        => todo("alignment {}", .{ele}),
        else => unreachable,
    };
    try writer.print(
        \\pub fn Start{f}Vector(__builder: *Builder, num_elems: i32) !u32 {{
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
    const field_ty = field.Type().?;
    const field_base_ty = field_ty.BaseType();

    if (fb.idl.isScalar(field_base_ty)) {
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
            .Obj => if (o.IsStruct())
                try getStructFieldOfStruct(o, field, schema, imports, writer)
            else
                try getStructFieldOfTable(o, field, schema, imports, writer),
            .String => try getStringField(o, field, schema, imports, writer),
            .Vector => {
                if (field_ty.Element() == .Obj) {
                    try getMemberOfVectorOfStruct(o, field, schema, imports, writer);
                    // TODO(michaeltle): Support querying fixed struct by key.
                    // Currently, we only support keyed tables.
                    const struct_def = schema.Objects(@as(u32, @bitCast(field_ty.Index()))).?;
                    if (!struct_def.IsStruct()) {
                        const mkey_field = blk: {
                            var i: u32 = 0;
                            while (i < struct_def.FieldsLen()) : (i += 1) {
                                const f = struct_def.Fields(i).?;
                                if (f.Key()) break :blk f;
                            }
                            break :blk null;
                        };
                        if (mkey_field) |key_field|
                            try getMemberOfVectorOfStructByKey(
                                o,
                                field,
                                key_field,
                                schema,
                                imports,
                                writer,
                            );
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
            .Union => try getUnionField(
                o,
                field,
                schema,
                imports,
                writer,
            ),
            else => unreachable,
        }
    }
    if (fb.idl.isVector(field_base_ty)) {
        try getVectorLen(o, field, imports, writer);
        if (field_ty.Element() == .UByte)
            try getUByteSlice(o, field, imports, writer);
    }
}

fn mutateScalarFieldOfStruct(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    try writer.print(
        \\pub fn Mutate{0f}(rcv: {1s}, n: {2f}) bool {{
        \\return rcv._tab._tab.mutate({2f}, rcv._tab._tab.pos + {3}, n);
        \\}}
        \\
        \\
    , .{ fname_camel_upper, lastName(o.Name()), fty_fmt, field.Offset() });
}

fn mutateScalarFieldOfTable(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const fty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );
    try writer.print(
        \\pub fn Mutate{0f}(rcv: {1s}, n: {2f}) bool {{
        \\return rcv._tab.mutateSlot({2f}, {3}, n);
        \\}}
        \\
        \\
    , .{ fname_camel_upper, lastName(o.Name()), fty_fmt, field.Offset() });
}

fn mutateElementOfVectorOfNonStruct(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const ele_tyname = zigScalarTypename(field_ty.Element());
    try writer.print(
        \\pub fn Mutate{0f}(rcv: {1s}, j: usize, n: {2s}) bool 
    , .{ fname_camel_upper, lastName(o.Name()), ele_tyname });
    try offsetPrefix(field, writer);
    try writer.print(
        \\const a = rcv._tab.vector(o);
        \\return rcv._tab.mutate({0s}, a + @as(u32, @intCast(j)) * {1}, n);
        \\}}
        \\return false;
        \\}}
        \\
        \\
    , .{ ele_tyname, inlineSize(field_ty, schema) });
}

/// Generate a struct field setter, conditioned on its child type(s).
fn genStructMutator(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const field_ty = field.Type().?;
    const field_base_ty = field_ty.BaseType();
    if (fb.idl.isScalar(field_base_ty)) {
        try if (o.IsStruct())
            mutateScalarFieldOfStruct(o, field, schema, imports, writer)
        else
            mutateScalarFieldOfTable(o, field, schema, imports, writer);
    } else if (field_base_ty == .Vector) {
        const ele = field_ty.Element();
        if (fb.idl.isScalar(ele))
            try mutateElementOfVectorOfNonStruct(o, field, schema, imports, writer);
    }
}

/// Generate struct or table methods.
fn genStruct(
    o: Object,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    // TODO if (o.generated) return;

    try genComment(o, .doc, writer);

    try genNativeStruct(o, schema, imports, writer);

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
        const field = o.Fields(getFieldIdxById(o, i).?).?;
        if (field.Deprecated()) continue;

        try genComment(field, .doc, writer);
        try genStructAccessor(o, field, schema, imports, writer);
        try genStructMutator(o, field, schema, imports, writer);

        // TODO(michaeltle): Support querying fixed struct by key. Currently,
        // we only support keyed tables.
        if (!o.IsStruct() and field.Key()) {
            try genKeyCompare(o, field, imports, writer);
            try genLookupByKey(o, field, schema, imports, writer);
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

    try writer.print(
        \\pub fn Unpack(rcv: {0s}, __pack_opts: fb.common.PackOptions) !{0s}T {{
        \\return {0s}T.Unpack(rcv, __pack_opts);
        \\}}
        \\
    , .{lastName(o.Name())});

    if (isRootTable(o.Name(), schema)) {
        // Check if a buffer has the identifier.
        _ = try writer.write(
            \\pub fn BufferHasIdentifier(buf: []const u8, off: u32) bool {
            \\return fb.BufferHasIdentifier(buf, off, __file_ident, false);
            \\}
            \\
            \\pub fn SizePrefixedBufferHasIdentifier(buf: []const u8, off: u32) bool {
            \\return fb.BufferHasIdentifier(buf, off, __file_ident, true);
            \\}
            \\
        );
    }

    // Finish a buffer with a given root object:
    try writer.print(
        \\pub fn FinishBuffer(__builder: *Builder, root: u32) !void {{
        \\return {s};
        \\}}
        \\
        \\
    , .{if (isRootTable(o.Name(), schema))
        \\__builder.finishWithFileIdentifier(root, __file_ident)
    else
        \\__builder.Finish(root)
    });
    try writer.print(
        \\pub fn FinishSizePrefixedBuffer(__builder: *Builder,root: u32) !void {{
        \\return {s};
        \\}}
        \\
        \\
    , .{if (isRootTable(o.Name(), schema))
        \\__builder.finishSizePrefixedWithFileIdentifier(root, __file_ident)
    else
        \\__builder.FinishSizePrefixed(root)
    });

    _ = try writer.write(
        \\};
        \\
        \\
    );
}

fn genObjectTest(o: Object, writer: anytype) !void {
    const lastname = lastName(o.Name());

    try writer.print(
        \\test {{
        \\    var obj = {0s}T{{}};
        \\    var b = Builder.init(std.testing.allocator);
        \\    defer b.deinitAll();
        \\    const opts: fb.common.PackOptions = .{{ .allocator = std.testing.allocator }};
        \\    const end = try obj.Pack(&b, opts);
        \\    try b.finish(end);
        \\    const bytes = try b.finishedBytes();
        \\    var obj_packed = 
    , .{lastname});

    if (!o.IsStruct())
        try writer.print(
            \\{s}.GetRootAs(bytes, 0);
            \\
        , .{lastname})
    else
        try writer.print(
            \\fb.GetRootAs({s}, bytes, 0);
            \\
        , .{lastname});

    try writer.print(
        \\    const obj2 = try obj_packed.Unpack(opts);
        \\    var b2 = Builder.init(std.testing.allocator);
        \\    defer b2.deinitAll();
        \\    const end2 = try obj2.Pack(&b2, opts);
        \\    try b2.finish(end2);
        \\    try std.testing.expectEqualStrings(bytes, try b2.finishedBytes());
        \\}}
    , .{});
}

fn genEnumTest(e: Enum, writer: anytype) !void {
    if (!e.IsUnion()) return;
    const lastname = lastName(e.Name());
    try writer.print(
        \\test {{
        \\    var obj: {0s}T = .NONE;
        \\    var b = Builder.init(std.testing.allocator);
        \\    defer b.deinitAll();
        \\    const opts: fb.common.PackOptions = .{{ .allocator = std.testing.allocator }};
        \\    const end = try obj.Pack(&b, opts);
        \\    try b.finish(end);
        \\    const bytes = try b.finishedBytes();
        \\    const table = fb.Table.init(bytes, 0);
        \\    const obj2 = try {0s}T.Unpack(.NONE, table, opts);
        \\    var b2 = Builder.init(std.testing.allocator);
        \\    defer b2.deinitAll();
        \\    const end2 = try obj2.Pack(&b2, opts);
        \\    try b2.finish(end2);
        \\    try std.testing.expectEqualStrings(bytes, try b2.finishedBytes());
        \\}}
        \\
    , .{lastname});
}

fn genKeyCompare(o: Object, field: Field, imports: *TypenameSet, writer: anytype) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const base_ty = field_ty.BaseType();
    try writer.print(
        \\pub fn KeyCompare(o1: u32, o2: u32, buf: []u8) bool {{
        \\const obj1 = {0s}.init(buf, @as(u32, @intCast(buf.len)) - o1);
        \\const obj2 = {0s}.init(buf, @as(u32, @intCast(buf.len)) - o2);
        \\
    , .{lastName(o.Name())});

    if (base_ty == .String)
        try writer.print(
            \\return std.mem.lessThan(u8, obj1.{0f}(), obj2.{0f}());
            \\
        , .{fname_camel_upper})
    else
        try writer.print(
            \\return obj1.{0f}() < obj2.{0f}();
            \\
        , .{fname_camel_upper});
    try writer.print(
        \\}}
        \\
        \\
    , .{});
}

fn genLookupByKey(
    o: Object,
    field: Field,
    schema: Schema,
    imports: *TypenameSet,
    writer: anytype,
) !void {
    const fname_camel_upper = camelUpperFmt(field.Name(), imports);
    const field_ty = field.Type().?;
    const base_ty = field_ty.BaseType();
    const olastname = lastName(o.Name());
    const ty_fmt = TypeFmt.init(
        field_ty,
        schema,
        .keep_ns,
        imports,
        .{ .is_optional = field.Optional() },
    );

    try writer.print(
        \\pub fn LookupByKey(rcv: *{s}, key: {f}, vector_loc: u32, buf: []u8) bool {{
        \\var span = fb.encode.read(u32, buf[vector_loc - 4..][0..4]);
        \\var start: u32 = 0;
        \\
    , .{ olastname, ty_fmt });
    try writer.print(
        \\while (span != 0) {{
        \\var middle = span / 2;
        \\const table_off = fb.GetIndirectOffset(buf, vector_loc + 4 * (start + middle));
        \\const obj = {s}.init(buf, table_off);
        \\
    , .{olastname});
    if (base_ty == .String) try writer.print(
        "const order = std.mem.order(u8, obj.{f}(), key);\n",
        .{fname_camel_upper},
    ) else {
        try writer.print(
            \\const order = std.math.order(obj.{f}(), key);
            \\
        , .{fname_camel_upper});
    }

    try writer.print(
        \\if (order == .gt) {{
        \\span = middle; 
        \\}} else if (order == .lt) {{ 
        \\middle += 1;
        \\start += middle;
        \\span -= middle;
        \\}} else {{
        \\rcv.* = {s}.init(buf, table_off);
        \\return true;
        \\}}
        \\}}
        \\return false;
        \\}}
        \\
        \\
    , .{olastname});
}

pub fn generate(
    alloc: mem.Allocator,
    bfbs_path: []const u8,
    gen_path: []const u8,
    basename: []const u8,
    opts: anytype,
) !void {
    _ = opts;
    std.log.debug(
        "bfbs_path={s} gen_path={s} basename={s}",
        .{ bfbs_path, gen_path, basename },
    );
    var buf: [std.fs.max_path_bytes]u8 = undefined;
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
    const needs_imports = false;

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
        try genEnumTest(e, ewriter);

        try imports.put(e.Name(), if (e.IsUnion()) .Union else e.UnderlyingType().?.BaseType());
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
            schema,
        );
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
        try genStruct(o, schema, &imports, swriter);
        try genObjectTest(o, swriter);
        try imports.put(o.Name(), .Obj);
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
            schema,
        );
    }

    // std.debug.print("{s}\n", .{one_file_code.items});
    // const zig_filename = try std.mem.concat(alloc, u8, &.{ basename, ".fb.zig" });
    // const zig_filepath = try std.fs.path.join(alloc, &.{ gen_path, zig_filename });
    // const zig_file = try std.fs.cwd().createFile(zig_filepath, .{});
    // defer zig_file.close();
}
