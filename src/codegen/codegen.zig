const std = @import("std");
const fb = @import("flatbufferz");
const writer_mod = @import("writer.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const CodeWriter = writer_mod.CodeWriter;
const getBasename = writer_mod.getBasename;
const Options = types.Options;
const BaseType = types.BaseType;
const Schema = types.Schema;
const Prelude = types.Prelude;
const log = types.log;

const Object = union(enum) {
    enum_: types.Enum,
    object: types.Object,

    const Self = @This();
    const Tag = std.meta.Tag(Self);

    pub fn declarationFile(self: Self) []const u8 {
        return switch (self) {
            inline else => |t| t.DeclarationFile(),
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            inline else => |t| t.Name(),
        };
    }
};

fn getFilename(allocator: Allocator, opts: Options, name: []const u8) ![]const u8 {
    var res = std.ArrayList(u8).init(allocator);
    var writer = res.writer();
    if (opts.gen_path.len != 0) {
        try writer.writeAll(opts.gen_path);
        try writer.writeByte(std.fs.path.sep);
    }
    for (name) |c| try writer.writeByte(if (c == '.') '/' else c);
    try writer.writeAll(opts.extension);
    return try res.toOwnedSlice();
}

fn createFile(fname: []const u8) !std.fs.File {
    const dir = std.fs.path.dirname(fname).?;
    std.fs.cwd().makePath(dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            log.err("couldn't make dir {?s}", .{dir});
            return e;
        },
    };

    return try std.fs.cwd().createFile(fname, .{});
}

fn format(allocator: Allocator, fname: []const u8, code: [:0]const u8) ![]const u8 {
    var ast = try std.zig.Ast.parse(allocator, code, .zig);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        for (ast.errors) |err| {
            var buf = std.ArrayList(u8).init(allocator);
            defer buf.deinit();
            ast.renderError(err, buf.writer()) catch {};
            log.err("formatting {s}: {s}", .{ fname, buf.items });
        }
        return code;
    }

    return try ast.render(allocator);
}

// Caller owns memory.
fn getCodeBody(allocator: Allocator, code_writer: *CodeWriter, obj: Object) ![]const u8 {
    var res = std.ArrayList(u8).init(allocator);
    switch (obj) {
        .enum_ => |e| try code_writer.writeEnum(res.writer(), e),
        .object => |o| try code_writer.writeObject(res.writer(), o),
    }
    return res.toOwnedSlice();
}

// Caller owns memory.
fn getCode(allocator: Allocator, opts: Options, prelude: Prelude, schema: Schema, obj: Object) ![:0]const u8 {
    var res = std.ArrayList(u8).init(allocator);
    var code_writer = CodeWriter.init(allocator, schema, opts);
    defer code_writer.deinit();

    // Write code body to temporary buffer to gather import declarations.
    const code_body = try getCodeBody(allocator, &code_writer, obj);
    defer allocator.free(code_body);

    try code_writer.writePrelude(res.writer(), prelude, obj.name());
    try res.appendSlice(code_body);
    return try res.toOwnedSliceSentinel(0);
}

fn writeFile(allocator: Allocator, opts: Options, prelude: Prelude, schema: Schema, obj: Object) !void {
    const fname = try getFilename(allocator, opts, obj.name());
    defer allocator.free(fname);
    var file = try createFile(fname);
    defer file.close();

    const code = try getCode(allocator, opts, prelude, schema, obj);
    defer allocator.free(code);

    const formatted_code = try format(allocator, fname, code);
    defer allocator.free(formatted_code);

    try file.writeAll(formatted_code);
}

const Names = std.ArrayList([]const u8);

fn writeFiles(
    allocator: Allocator,
    names: *Names,
    opts: Options,
    prelude: Prelude,
    schema: Schema,
    comptime kind: Object.Tag,
) !void {
    const len = switch (kind) {
        .enum_ => schema.EnumsLen(),
        .object => schema.ObjectsLen(),
    };

    for (0..len) |i| {
        const obj: Object = switch (kind) {
            .enum_ => .{ .enum_ = schema.Enums(i).? },
            .object => .{ .object = schema.Objects(i).? },
        };
        const decl_file = obj.declarationFile();
        const same_file = decl_file.len == 0 or std.mem.eql(u8, decl_file, prelude.file_ident);
        if (!same_file) continue;

        try writeFile(allocator, opts, prelude, schema, obj);
        try names.append(obj.name());
    }
}

// Caller owns memory
fn getSchema(allocator: Allocator, bfbs_path: []const u8) !Schema {
    const f = try std.fs.cwd().openFile(bfbs_path, .{});
    defer f.close();
    const bfbs = try f.readToEndAlloc(allocator, std.math.maxInt(u16));
    return Schema.GetRootAs(bfbs, 0);
}

// Caller owns memory
fn getFileIdent(allocator: Allocator, bfbs_path: []const u8) ![]const u8 {
    const basename = getBasename(bfbs_path);
    const no_ext = basename[0 .. basename.len - 5];
    return try std.fmt.allocPrint(allocator, "//{s}.fbs", .{no_ext});
}

pub fn codegen(allocator: Allocator, bfbs_path: []const u8, filename_noext: []const u8, opts: Options) !void {
    const schema = try getSchema(allocator, bfbs_path);
    defer allocator.free(schema._tab.bytes);

    const file_ident = try getFileIdent(allocator, bfbs_path);
    defer allocator.free(file_ident);
    log.debug("file_ident={s}", .{file_ident});

    const prelude = types.Prelude{
        .bfbs_path = bfbs_path,
        .filename_noext = filename_noext,
        .file_ident = file_ident,
    };

    var names = Names.init(allocator);
    defer names.deinit();

    try writeFiles(allocator, &names, opts, prelude, schema, .enum_);
    try writeFiles(allocator, &names, opts, prelude, schema, .object);

    // for (names.items) |name| log.debug("{s} {s}", .{ name});
}
