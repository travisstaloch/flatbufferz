const std = @import("std");

pub const GenStep = struct {
    step: std.build.Step,
    b: *std.build.Builder,
    sources: std.ArrayListUnmanaged(std.build.FileSource) = .{},
    cache_path: []const u8,
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
        const self = try b.allocator.create(GenStep);
        const cache_root = try std.fs.path.resolve(
            b.allocator,
            &.{b.cache_root.path orelse "."},
        );

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
            }),
            .b = b,
            .cache_path = cache_path,
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
        run_cmd.addArgs(&.{ "-l", lib_path });
        run_cmd.addArgs(args);
        run_cmd.addArgs(files);

        self.step.dependOn(&run_cmd.step);

        return self;
    }
};
