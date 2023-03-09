const std = @import("std");
const sdk = @import("sdk.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const log_level = b.option(
        std.log.Level,
        "log-level",
        "The log level for the application. default .err",
    ) orelse .err;
    const build_options = b.addOptions();
    build_options.addOption(std.log.Level, "log_level", log_level);

    // expose module 'flatbufferz' to dependees
    const lib_mod = b.addModule(
        "flatbufferz",
        .{ .source_file = .{ .path = "src/lib.zig" } },
    );
    try lib_mod.dependencies.put("flatbufferz", lib_mod);

    const zig_clap_pkg = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const zig_clap = zig_clap_pkg.module("clap");
    const exe = b.addExecutable(.{
        .name = "flatc-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("flatbufferz", lib_mod);
    exe.addModule("zig-clap", zig_clap);
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

    // generate files that need to be avaliable in tests
    var gen_step = try sdk.GenStep.create(b, exe, &.{
        "examples/sample.fbs",
    });
    const gen_mod = b.createModule(.{
        .source_file = gen_step.module.source_file,
        .dependencies = &.{.{ .name = "flatbufferz", .module = lib_mod }},
    });

    const exe_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_tests.addOptions("build_options", build_options);
    exe_tests.addModule("flatbufferz", lib_mod);
    exe_tests.addModule("generated", gen_mod);
    exe_tests.main_pkg_path = ".";
    // exe_tests.step.dependOn(b.getInstallStep());
    exe_tests.step.dependOn(&gen_step.step);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);

    // TODO remove this flag.
    const build_sample = b.option(
        bool,
        "build-sample",
        "Wether to build sample",
    ) orelse false;
    if (build_sample) {
        const sample_exe = b.addExecutable(.{
            .name = "sample",
            .root_source_file = .{ .path = "examples/sample_binary.zig" },
            .target = target,
            .optimize = optimize,
        });
        sample_exe.addOptions("build_options", build_options);
        sample_exe.addModule("flatbufferz", lib_mod);
        sample_exe.addModule("generated", gen_mod);
        sample_exe.step.dependOn(&gen_step.step);

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
}
