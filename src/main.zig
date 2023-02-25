const std = @import("std");

const _flatc = @import("flatc.zig");
const Compiler = _flatc.Compiler;
const idl_gen_zig = @import("idl_gen_zig.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    // const flatbuffers_version = idl_parser.VERSION;

    const args = try std.process.argsAlloc(alloc);
    _flatc.program_name = args[0];
    var flatc = Compiler{ .params = &_flatc.params, .allocator = alloc };

    var zig_code_generator = idl_gen_zig.init(alloc);
    try flatc.registerCodeGenerator(
        _flatc.Option.init(
            "z",
            "zig",
            "",
            "Generate Zig code for tables/structs",
        ),
        &zig_code_generator,
    );

    const options = try flatc.parseFromCli(args);

    return flatc.compile(options);
}
