const common = @import("common.zig");
const todo = common.todo;
const idl = @import("idl.zig");
const idl_parser = @import("idl_parser.zig");
const Parser = idl_parser.Parser;

pub const CodeGenerator = struct {
    supportsRootFileGeneration: *const fn (*const CodeGenerator) bool = supportsRootFileGeneration_default,
    language: idl.Options.Language,
    supports_bfbs_generation: bool = false,

    fn supportsRootFileGeneration_default(_: *const CodeGenerator) bool {
        return true;
    }
    pub fn generateRootFile(cg: *const CodeGenerator, parser: *const Parser, output_path: []const u8) !void {
        _ = cg;
        _ = parser;
        _ = output_path;
        todo("generateRootFile", .{});
    }
};
