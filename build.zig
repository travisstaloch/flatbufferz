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

    b.installArtifact(exe);

    const exe_run = b.addRunArtifact(exe);
    exe_run.has_side_effects = true;
    exe_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| exe_run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&exe_run.step);

    // generate files that need to be avaliable in tests
    const gen_step = try sdk.GenStep.create(b, exe, &.{
        "examples/sample.fbs",
        "examples/monster_test.fbs",
        "examples/include_test/order.fbs",
        "examples/include_test/sub/no_namespace.fbs",
        "examples/optional_scalars.fbs",
    }, &.{ "-I", "examples/include_test", "-I", "examples/include_test/sub" }, "flatc-zig");
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
    exe_tests.step.dependOn(&gen_step.step);

    const test_step = b.step("test", "Run unit tests");
    const tests_run = b.addRunArtifact(exe_tests);
    test_step.dependOn(&tests_run.step);
    tests_run.has_side_effects = true;

    // TODO remove this flag.
    const build_sample = b.option(
        bool,
        "build-sample",
        "Wether to build the examples/sample_binary.zig exe",
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

        b.installArtifact(sample_exe);

        const sample_run = b.addRunArtifact(sample_exe);
        sample_run.has_side_effects = true;
        const sample_run_step = b.step("run-sample", "Run the app");
        sample_run_step.dependOn(&sample_run.step);
    }

    const flatbuffers_dep = b.dependency("flatbuffers", .{
        .target = target,
        .optimize = optimize,
    });
    const flatc = flatbuffers_dep.artifact("flatc");
    b.installArtifact(flatc); // doesn't do anything
    build_options.addOptionArtifact("flatc_exe_path", flatc);
    exe.step.dependOn(&flatc.step);

    const flatc_run = b.addRunArtifact(flatc);
    flatc_run.has_side_effects = true;
    flatc_run.cwd = b.pathFromRoot(".");
    if (b.args) |args| flatc_run.addArgs(args);
    const flatc_run_step = b.step("flatc", "Run packaged flatc compiler");
    flatc_run_step.dependOn(&flatc_run.step);
}
