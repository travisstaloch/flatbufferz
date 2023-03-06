const std = @import("std");
const mem = std.mem;
const fb = @import("flatbufferz");
const clap = @import("zig-clap");
const util = fb.util;

pub const std_options = struct {
    pub const log_level = std.meta.stringToEnum(
        std.log.Level,
        @tagName(@import("build_options").log_level),
    ).?;
};

fn usage(params: []const clap.Param(clap.Help), res: anytype) !void {
    std.debug.print("usage: {s} <args> <files>\n<files>: either .fbs or .bfbs files depending on args.\n<args>:\n", .{res.exe_arg.?});
    try clap.help(std.io.getStdErr().writer(), clap.Help, params, .{});
}

const clap_params = clap.parseParamsComptime(
    \\-h, --help              Display this help and exit.
    \\--bfbs-to-fbs           Interpret positionals as .bfbs files and convert them to .fbs.  Prints to stdout.
    \\-o, --output-path <str> Path to write generated content to
    \\-I, --include-dir <str>... Adds an include directory which gets passed on to flatc.
    \\--gen-onefile           Write all output to a single file.
    \\--no-gen-object-api     Don't generate an additional object-based API.
    //    \\--keep-prefix           Keep original prefix of schema include statements.
    \\<str>...                Files
    \\
);

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    // parse cli args
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &clap_params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |e| {
        diag.report(std.io.getStdErr().writer(), e) catch {};
        return e;
    };
    defer res.deinit();

    const stdout = std.io.getStdOut().writer();

    if (res.args.@"bfbs-to-fbs") {
        for (res.positionals) |filename| {
            try util.expectExtension(".bfbs", filename);
            try fb.binary_tools.bfbsToFbs(alloc, filename, stdout);
        }
    } else if (res.args.help) {
        try usage(&clap_params, res);
    } else {
        // setup a flatc command args used to gen .bfbs from .fbs args
        var argv = std.ArrayList([]const u8).init(alloc);
        try argv.appendSlice(&.{ "flatc", "-b", "--schema", "--bfbs-comments", "--bfbs-builtins", "--bfbs-gen-embed" });
        for (res.args.@"include-dir") |inc| try argv.appendSlice(&.{ "-I", inc });

        const gen_path = res.args.@"output-path" orelse "";
        for (res.positionals, 0..) |filename, i| {
            const is_fbs = util.hasExtension(".fbs", filename);
            const is_bfbs = util.hasExtension(".bfbs", filename);
            const ext_offset: u8 = if (is_fbs) 4 else if (is_bfbs) 5 else 0;
            const filename_noext = filename[0 .. filename.len - ext_offset];
            const dirname = std.fs.path.dirname(filename) orelse "";
            const bfbs_path = if (is_fbs) blk: {
                if (i != 0) argv.items.len -= 3;
                const gen_path_full = try std.fs.path.join(alloc, &.{ gen_path, dirname });
                try argv.appendSlice(&.{ "-o", gen_path_full });
                try argv.append(filename);
                const exec_res = try std.ChildProcess.exec(.{ .allocator = alloc, .argv = argv.items });
                // std.debug.print("term={}\n", .{exec_res.term});
                // std.debug.print("stderr={s}\n", .{exec_res.stderr});
                // std.debug.print("stdout={s}\n", .{exec_res.stdout});
                if (exec_res.term != .Exited or exec_res.term.Exited != 0) {
                    for (argv.items) |it| std.debug.print("{s} ", .{it});
                    std.debug.print("\n", .{});
                    std.debug.print("{s}", .{exec_res.stderr});
                    std.os.exit(1);
                }

                const bfbs_filename = try std.mem.concat(alloc, u8, &.{ filename_noext, ".bfbs" });
                const bfbs_path = try std.fs.path.join(alloc, &.{ gen_path, bfbs_filename });
                break :blk bfbs_path;
            } else if (is_bfbs)
                filename
            else {
                std.log.err(
                    "unexpected extension '{s}' in '{s}'. expected either .fbs or .bfbs.",
                    .{ std.fs.path.extension(filename), filename },
                );
                std.os.exit(1);
            };
            try fb.codegen.generate(alloc, bfbs_path, gen_path, filename_noext, res.args);
        }
    }
}
