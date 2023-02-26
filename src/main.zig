const std = @import("std");
const mem = std.mem;
const fb = @import("flatbufferz");
const clap = @import("zig-clap");

pub const std_options = struct {
    pub const log_level = std.meta.stringToEnum(
        std.log.Level,
        @tagName(@import("build_options").log_level),
    ).?;
};

const Options = struct {
    @"bfbs-to-fbs": bool = false,
    @"output-path": []const u8 = "",

    pub const shorthands = .{
        .o = "output-path",
    };
    // pub fn format(
    //     opts: Options,
    //     comptime _: []const u8,
    //     _: std.fmt.FormatOptions,
    //     writer: anytype,
    // ) !void {
    //     inline for (std.meta.fields(Options)) |fld| {
    //         const fmt = if (comptime std.meta.trait.isZigString(fld.type))
    //             "{s}"
    //         else
    //             "{any}";
    //         try writer.print("\t{s} = " ++ fmt ++ "\n", .{
    //             fld.name,
    //             @field(opts, fld.name),
    //         });
    //     }
    // }
};

const Error = error{Unexpected};
fn err(comptime fmt: []const u8, args: anytype) Error {
    std.log.err(fmt, args);
    return error.Unexpected;
}

fn usage(params: []const clap.Param(clap.Help), res: anytype) !void {
    std.debug.print("usage: {s} <args> <files>\nargs:\n", .{res.exe_arg.?});
    try clap.help(std.io.getStdErr().writer(), clap.Help, params, .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\--bfbs-to-fbs           Interpret positionals as .bfbs files and print .fbs to stdout.
        \\-o, --output-path <str> Path to write generated content to
        \\<str>...                Files
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |e| {
        diag.report(std.io.getStdErr().writer(), e) catch {};
        return e;
    };
    defer res.deinit();

    // try usage(&params, res);
    const stdout = std.io.getStdOut().writer();
    // try diag.report(stdout, error.asfd);
    if (res.args.@"bfbs-to-fbs") {
        for (res.positionals) |filename|
            // TODO err if filename extension isn't bfbs?
            try fb.binary_tools.bfbsToFbs(alloc, filename, stdout);
    }
}
