const std = @import("std");
const mem = std.mem;
const idl = @import("idl.zig");
const code_generator = @import("code_generator.zig");
const CodeGenerator = code_generator.CodeGenerator;
const Error = CodeGenerator.Error;
const Namer = @import("Namer.zig");
const util = @import("util.zig");
const Case = util.Case;
const idl_parser = @import("idl_parser.zig");
const Parser = idl_parser.Parser;
const fb = @import("flatbuffers");
const common = fb.common;
const todo = common.todo;
const idl_namer = @import("idl_namer.zig");
const withFlagOptions = idl_namer.withFlagOptions;
const code_generators = @import("code_generators.zig");
const CodeWriter = code_generators.CodeWriter;

pub fn init(allocator: std.mem.Allocator) CodeGenerator {
    return .{
        .language = .zig,
        .supportsRootFileGeneration = supportsRootFileGeneration,
        .generateRootFile = generateRootFile,
        .allocator = allocator,
    };
}

pub fn zigDefaultConfig() Namer.Config {
    // Historical note: We've been using "keep" casing since the original
    // implementation, presumably because Flatbuffers schema style and Rust style
    // roughly align. We are not going to enforce proper casing since its an
    // unnecessary breaking change.
    return .{
        .types = Case.Keep,
        .constants = Case.Snake,
        .methods = Case.LowerCamel,
        .functions = Case.LowerCamel,
        .fields = Case.Keep,
        .variables = Case.Unknown, // Unused.
        .variants = Case.Keep,
        .enum_variant_seperator = ".",
        .escape_keywords = Namer.Config.Escape.BeforeConvertingCase,
        .namespaces = Case.Snake,
        .namespace_seperator = ".",
        .object_prefix = "",
        .object_suffix = "T",
        .keyword_prefix = "",
        .keyword_suffix = "_",
        .filenames = Case.Snake,
        .directories = Case.Snake,
        .output_path = "",
        .filename_suffix = "_generated",
        .filename_extension = ".zig",
    };
}

fn supportsRootFileGeneration(_: *const CodeGenerator) bool {
    return true;
}

fn generateRootFile(cg: *const CodeGenerator, parser: Parser, output_path: []const u8) Error!void {
    std.log.debug("idl_gen_zig generateRootFile() language={s} output_path={s}", .{ @tagName(cg.language), output_path });
    try generateZigModuleRootFile(cg, parser, output_path);
}

/// We gather the symbols into a tree of namespaces (which are zig mods) and
/// generate a file that gathers them all.
const Module = struct {
    sub_modules: std.StringHashMapUnmanaged(*Module) = .{},
    generated_files: std.ArrayListUnmanaged([]const u8) = .{},

    /// Add a symbol into the tree.
    pub fn insert(
        m: *Module,
        alloc: mem.Allocator,
        namer: Namer,
        symbol: idl.Definition,
    ) !void {
        // _ = alloc;
        var current_module: ?*Module = m;
        // for (auto it = symbol.defined_namespace.components.begin();
        for (symbol.defined_namespace.?.components.items) |it| {
            // it != symbol.defined_namespace.components.end(); it++) {
            std.log.debug("it={s}", .{it});
            var ns_component = std.ArrayList(u8).init(alloc);
            try namer.namespace(it, ns_component.writer());
            var iter = current_module.?.sub_modules.iterator();
            while (iter.next()) |x|
                std.log.debug("x={} ns_component={s}", .{ x, ns_component.items });
            current_module = current_module.?.sub_modules.get(ns_component.items);
        }
        if (true) todo("asdf", .{});
        // const parts = try namer.file(alloc, symbol.name, &.{.Extension});
        // const file = try std.fs.path.join(alloc, &parts);
        // try current_module.generated_files.append(alloc, file);
    }
    // Recursively create the importer file.
    pub fn generateImports(m: Module, code: *CodeWriter) !void {
        // for (auto it = sub_modules.begin(); it != sub_modules.end(); it++) {
        _ = code;
        var iter = m.sub_modules.iterator();
        while (iter.next()) |it| {
            // for (m.sub_modules.items) |it| {
            _ = it;

            // code += "pub mod " + it.first + " {";
            // code.IncrementIdentLevel();
            // code += "use super::*;";
            // it.second.GenerateImports(code);
            // code.DecrementIdentLevel();
            // code += "} // " + it.first;
        }
        // for (auto it = generated_files.begin(); it != generated_files.end();
        //      it++) {
        for (m.generated_files.items) |it| {
            // code += "mod " + *it + ";";
            // code += "pub use self::" + *it + "::*;";
            _ = it;
        }
    }
};

fn generateZigModuleRootFile(cg: *const CodeGenerator, parser: Parser, output_dir: []const u8) !void {
    std.log.debug("idl_gen_zig generateZigModuleRootFile() output_path={s} zig_module_root_file={}", .{ output_dir, parser.opts.zig_module_root_file });
    // if (!parser.opts.zig_module_root_file) {
    //     // Don't generate a root file when generating one file. This isn't an error
    //     // so return true.
    //     return;
    // }
    // const zig_keywords = blk: {
    //     // var keywords: []const []const u8 = &.{};
    //     var keywords: std.StringHashMapUnmanaged(void) = .{};
    //     // for (std.zig.Token.keywords.kvs) |kv| keywords = keywords ++ [1][]const u8{kv.key};
    //     for (std.zig.Token.keywords.kvs) |kv| try keywords.put(cg.allocator, kv.key, {});
    //     break :blk keywords;
    // };
    var namer = Namer.init(withFlagOptions(zigDefaultConfig(), parser.opts, output_dir));

    var root_module = Module{};
    // for (auto it = parser.enums_.vec.begin(); it != parser.enums_.vec.end();
    //      it++) {
    for (parser.enums_.vec.items) |it| {
        try root_module.insert(cg.allocator, namer, it.base);
    }
    // for (auto it = parser.structs_.vec.begin(); it != parser.structs_.vec.end();
    //      it++) {
    for (parser.structs_.vec.items) |it| {
        try root_module.insert(cg.allocator, namer, it.base);
    }
    // CodeWriter code("  ");
    var code = CodeWriter.init("  ", cg.allocator);
    // TODO(caspern): Move generated warning out of BaseGenerator.
    try code.writeLine("// Automatically generated by the Flatbuffers compiler. " ++
        "Do not modify.");
    try code.writeLine("// @generated");
    try root_module.generateImports(&code);
    const output_path = try std.fs.path.join(cg.allocator, &.{ output_dir, "lib.zig" });
    defer cg.allocator.free(output_path);
    try util.saveFile(output_path, code.buf.items, false);
    code.buf.clearRetainingCapacity();
}
