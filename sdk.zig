const std = @import("std");

pub const GenStep = struct {
    step: std.build.Step,
    b: *std.build.Builder,
    sources: std.ArrayListUnmanaged(std.build.FileSource) = .{},
    cache_path: []const u8,
    lib_file: std.build.GeneratedFile,
    module: *std.Build.Module,

    /// init a GenStep, create zig-cache/flatc-zig if not exists, setup
    /// dependencies, and setup args to exe.run()
    pub fn create(
        b: *std.build.Builder,
        exe: *std.build.LibExeObjStep,
        files: []const []const u8,
    ) !*GenStep {
        const self = b.allocator.create(GenStep) catch unreachable;
        const cache_root = std.fs.path.resolve(
            b.allocator,
            &.{b.cache_root.path orelse "."},
        ) catch @panic("OOM");
        const flatc_zig_path = "flatc-zig";
        const cache_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_root, flatc_zig_path },
        );
        const lib_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_path, "lib.zig" },
        );

        self.* = GenStep{
            .step = std.build.Step.init(
                .custom,
                "build-template",
                b.allocator,
                make,
            ),
            .b = b,
            .cache_path = cache_path,
            .lib_file = .{
                .step = &self.step,
                .path = lib_path,
            },
            .module = b.createModule(.{ .source_file = .{ .path = lib_path } }),
        };

        for (files) |file| {
            const source = try self.sources.addOne(b.allocator);
            source.* = .{ .path = file };
            source.addStepDependencies(&self.step);
        }

        const run_cmd = exe.run();
        run_cmd.step.dependOn(&exe.step);

        try b.cache_root.handle.makePath(flatc_zig_path);

        run_cmd.addArgs(&.{ "-o", cache_path, "-I", "examples" });

        for (files) |file|
            run_cmd.addArg(file);

        self.step.dependOn(&run_cmd.step);

        return self;
    }

    /// iterate over all files in self.cache_path
    /// and create a 'lib.zig' file at self.lib_file.path which exports all
    /// generated .fb.zig files
    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(GenStep, "step", step);

        var file = try std.fs.cwd().createFile(self.lib_file.path.?, .{});
        defer file.close();
        const writer = file.writer();

        // TODO include sub dirs
        var dir = try std.fs.cwd().openIterableDir(self.cache_path, .{});
        defer dir.close();
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .File) continue; // TODO include sub dirs
            const endidx = std.mem.lastIndexOf(u8, entry.name, ".fb.zig") orelse
                continue;

            const startidx = if (std.mem.lastIndexOfScalar(
                u8,
                entry.name[0..endidx],
                '/',
            )) |i| i + 1 else 0;
            const name = entry.name[startidx..endidx];
            // remove illegal characters to make a zig identifier
            var buf: [256]u8 = undefined;
            std.mem.copy(u8, &buf, name);
            if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') {
                std.log.err(
                    "invalid identifier '{s}'. filename must start with alphabetic or underscore",
                    .{name},
                );
                return error.InvalidIdentifier;
            }
            for (name[1..], 0..) |c, i| {
                if (!std.ascii.isAlphanumeric(c)) buf[i + 1] = '_';
            }
            const path = if (std.mem.startsWith(u8, entry.name, "examples/"))
                entry.name[0..endidx]["examples/".len..]
            else
                entry.name[0..endidx];
            try writer.print(
                \\pub const {s} = @import("{s}.fb.zig");
                \\
            , .{ buf[0..name.len], path });
        }
    }
};
