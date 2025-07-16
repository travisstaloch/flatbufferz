const std = @import("std");
const mem = std.mem;
const build_options = @import("build_options");

const flagset = @import("flagset");
const fb = @import("flatbufferz");
const util = fb.util;

pub const std_options: std.Options = .{
    .log_level = std.meta.stringToEnum(
        std.log.Level,
        @tagName(@import("build_options").log_level),
    ).?,
};

const flags = [_]flagset.Flag{
    .init(bool, "bfbs-to-fbs", .{ .short = 'f', .desc = "Interpret positionals as .bfbs files and convert them to .fbs.  Prints to stdout.", .default_value_ptr = &false }),
    .init(?[]const u8, "output-path", .{ .short = 'o', .desc = "Path to write generated content to." }),
    .init([]const u8, "include-dir", .{ .kind = .list, .short = 'I', .desc = "Adds an include directory which gets passed on to flatc." }),
    // \\--gen-onefile           Write all output to a single file.
    // \\--no-gen-object-api     Don't generate an additional object-based API.
    // \\--keep-prefix           Keep original prefix of schema include statements.
};

fn usage() void {
    std.debug.print("{f}", .{flagset.fmtUsage(&flags, ": <25", .full,
        \\
        \\usage: <options> <files>
        \\
        \\files: either .fbs or .bfbs files.
        \\
        \\
    )});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();

    // parse cli args
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    var res = flagset.parseFromIter(&flags, args, .{ .allocator = alloc }) catch |e| switch (e) {
        error.HelpRequested => {
            usage();
            return;
        },
        else => return e,
    };
    defer res.deinit(alloc);

    var stdout = std.fs.File.stdout().writer(&.{});

    if (res.parsed.@"bfbs-to-fbs") {
        while (res.unparsed_args.next()) |filename| {
            try util.expectExtension(".bfbs", filename);
            try fb.binary_tools.bfbsToFbs(alloc, filename, &stdout.interface);
        }
    } else {
        // setup a flatc command args used to gen .bfbs from .fbs args
        var argv = std.ArrayList([]const u8).init(alloc);
        try argv.appendSlice(&.{
            build_options.flatc_exe_path,
            "-b",
            "--schema",
            "--bfbs-comments",
            "--bfbs-builtins",
            "--bfbs-gen-embed",
            // "--raw-binary",
            // "--bfbs-filenames", // TODO consider providing this arg?
        });
        for (res.parsed.@"include-dir".items) |inc|
            try argv.appendSlice(&.{ "-I", inc });

        var tmp_unparsed = res.unparsed_args;
        if (tmp_unparsed.next() == null) {
            usage();
            return error.NoPositionals;
        }

        const gen_path = res.parsed.@"output-path" orelse "";
        var i: usize = 0;
        while (res.unparsed_args.next()) |filename| : (i += 1) {
            const is_fbs = util.hasExtension(".fbs", filename);
            const is_bfbs = util.hasExtension(".bfbs", filename);
            const ext_offset: u8 = if (is_fbs) 4 else if (is_bfbs) 5 else 0;
            const filename_noext = filename[0 .. filename.len - ext_offset];
            const dirname = std.fs.path.dirname(filename) orelse "";
            const bfbs_path = if (is_fbs) blk: {
                // remove previous ["-o", gen_path_full, filename] args
                if (i != 0) argv.items.len -= 3;
                const gen_path_full = try std.fs.path.join(alloc, &.{ gen_path, dirname });
                try argv.appendSlice(&.{ "-o", gen_path_full });
                try argv.append(filename);
                std.log.debug("argv={s}\n", .{argv.items});
                const exec_res = try std.process.Child.run(.{ .allocator = alloc, .argv = argv.items });
                // std.debug.print("term={}\n", .{exec_res.term});
                // std.debug.print("stderr={s}\n", .{exec_res.stderr});
                // std.debug.print("stdout={s}\n", .{exec_res.stdout});
                if (exec_res.term != .Exited or exec_res.term.Exited != 0) {
                    for (argv.items) |it| std.debug.print("{s} ", .{it});
                    std.debug.print("\nerror: flatc command failure:\n", .{});
                    std.debug.print("{s}\n", .{exec_res.stderr});
                    if (exec_res.stdout.len > 0) try stdout.interface.print("{s}\n", .{exec_res.stdout});
                    std.process.exit(1);
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
                std.process.exit(1);
            };
            try fb.codegen.generate(alloc, bfbs_path, gen_path, filename_noext, res.parsed);
        }
    }
}
