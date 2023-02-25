const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const log_level = b.option(
        std.log.Level,
        "log-level",
        "The log level for the application. default .err",
    ) orelse .err;
    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);

    const exe = b.addExecutable(.{
        .name = "flatbuffers-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addOptions("build_options", build_options);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_cmd.condition = .always;
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib = b.createModule(.{ .source_file = .{ .path = "src/lib.zig" } });
    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests.addOptions("build_options", build_options);
    exe_tests.addModule("flatbuffers", lib);
    exe_tests.main_pkg_path = ".";
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    const sample_exe = b.addExecutable(.{
        .name = "sample",
        .root_source_file = .{ .path = "samples/sample_binary.zig" },
        .target = target,
        .optimize = optimize,
    });
    sample_exe.addOptions("build_options", build_options);
    sample_exe.addModule("flatbuffers", lib);
    sample_exe.install();

    const sample_run_cmd = sample_exe.run();
    sample_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        sample_run_cmd.addArgs(args);
    }
    sample_run_cmd.condition = .always;
    const sample_run_step = b.step("run-sample", "Run the app");
    sample_run_step.dependOn(&sample_run_cmd.step);
}
