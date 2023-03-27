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
        args: []const []const u8,
        cache_subdir: []const u8,
    ) !*GenStep {
        const self = b.allocator.create(GenStep) catch unreachable;
        const cache_root = std.fs.path.resolve(
            b.allocator,
            &.{b.cache_root.path orelse "."},
        ) catch @panic("OOM");

        const cache_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_root, cache_subdir },
        );
        const lib_path = try std.fs.path.join(
            b.allocator,
            &.{ cache_path, "lib.zig" },
        );

        self.* = GenStep{
            .step = std.build.Step.init(.{
                .id = .custom,
                .name = "build-template",
                .owner = b,
                .makeFn = make,
            }),
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

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&exe.step);

        try b.cache_root.handle.makePath(cache_subdir);

        run_cmd.addArgs(&.{ "-o", cache_path });
        run_cmd.addArgs(args);
        run_cmd.addArgs(files);

        self.step.dependOn(&run_cmd.step);

        return self;
    }

    /// iterate over all files in self.cache_path
    /// and create a 'lib.zig' file at self.lib_file.path which exports all
    /// generated .fb.zig files
    fn make(step: *std.build.Step, _: *std.Progress.Node) !void {
        const self = @fieldParentPtr(GenStep, "step", step);

        var file = try std.fs.cwd().createFile(self.lib_file.path.?, .{});
        defer file.close();
        const writer = file.writer();

        try self.visit(self.cache_path, writer);
    }

    // recursively visit path and child directories
    fn visit(self: *const GenStep, path: []const u8, writer: anytype) !void {
        var dir = try std.fs.cwd().openIterableDir(path, .{});
        defer dir.close();
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .Directory) {
                const sub_path = try std.fs.path.join(self.b.allocator, &.{ path, entry.name });
                defer self.b.allocator.free(sub_path);
                try self.visit(sub_path, writer);
                continue;
            }
            if (entry.kind != .File) continue;
            // extract file name identifier: a/b/foo.fb.zig => foo
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
            var fbs = std.io.fixedBufferStream(&buf);
            const fbswriter = fbs.writer();
            if (self.cache_path.len < path.len) {
                _ = try fbswriter.write(path[self.cache_path.len + 1 ..]);
                _ = try fbswriter.writeByte('_');
            }
            _ = try fbswriter.write(name);
            const ident = fbs.getWritten();
            if (!std.ascii.isAlphabetic(ident[0]) and ident[0] != '_') {
                std.log.err(
                    "invalid identifier '{s}'. filename must start with alphabetic or underscore",
                    .{ident},
                );
                return error.InvalidIdentifier;
            }
            for (ident, 0..) |c, i| {
                if (!(std.ascii.isAlphanumeric(c) or c == '-')) ident[i] = '_';
            }

            if (self.cache_path.len < path.len)
                try writer.print(
                    \\pub const {s} = @import("{s}{c}{s}.fb.zig");
                    \\
                , .{ ident, path[self.cache_path.len + 1 ..], std.fs.path.sep, entry.name[0..endidx] })
            else
                try writer.print(
                    \\pub const {s} = @import("{s}.fb.zig");
                    \\
                , .{ ident, entry.name[0..endidx] });
        }
    }
};
