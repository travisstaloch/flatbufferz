const std = @import("std");
const common = @import("common.zig");
const todo = common.todo;
const idl = @import("idl.zig");
const idl_parser = @import("idl_parser.zig");
const Parser = idl_parser.Parser;

pub const CodeGenerator = struct {
    supportsRootFileGeneration: *const fn (*const CodeGenerator) bool = supportsRootFileGeneration,
    generateRootFile: *const fn (*const CodeGenerator, Parser, []const u8) Error!void = generateRootFile,
    language: idl.Options.Language,
    supports_bfbs_generation: bool = false,
    allocator: std.mem.Allocator,

    pub const Error = error{} ||
        std.mem.Allocator.Error ||
        std.fs.File.OpenError ||
        std.fs.File.WriteError;

    fn supportsRootFileGeneration(cg: *const CodeGenerator) bool {
        todo("supportsRootFileGeneration() language={s}", .{@tagName(cg.language)});
    }
    fn generateRootFile(cg: *const CodeGenerator, parser: Parser, output_path: []const u8) Error!void {
        _ = parser;
        todo("generateRootFile() language={s} output_path={s}", .{ @tagName(cg.language), output_path });
    }
};
