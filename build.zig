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
        .{ .root_source_file = b.path("src/lib.zig") },
    );
    try lib_mod.import_table.put(b.allocator, "flatbufferz", lib_mod);

    const zig_clap_pkg = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const zig_clap = zig_clap_pkg.module("clap");

    const exe = b.addExecutable(.{
        .name = "flatc-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("flatbufferz", lib_mod);
    exe.root_module.addImport("zig-clap", zig_clap);
    exe.root_module.addOptions("build_options", build_options);

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
        .root_source_file = gen_step.module.root_source_file,
        .imports = &.{.{ .name = "flatbufferz", .module = lib_mod }},
    });
    const examples_mod = b.createModule(
        .{ .root_source_file = b.path("examples/lib.zig") },
    );

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_tests.root_module.addOptions("build_options", build_options);
    exe_tests.root_module.addImport("flatbufferz", lib_mod);
    exe_tests.root_module.addImport("generated", gen_mod);
    exe_tests.root_module.addImport("examples", examples_mod);
    exe_tests.step.dependOn(&gen_step.step);

    const test_step = b.step("test", "Run unit tests");
    const tests_run = b.addRunArtifact(exe_tests);
    test_step.dependOn(&tests_run.step);
    tests_run.has_side_effects = true;

    const sample_exe = b.addExecutable(.{
        .name = "sample",
        .root_source_file = b.path("examples/sample_binary.zig"),
        .target = target,
        .optimize = optimize,
    });
    sample_exe.root_module.addOptions("build_options", build_options);
    sample_exe.root_module.addImport("flatbufferz", lib_mod);
    sample_exe.root_module.addImport("generated", gen_mod);
    sample_exe.step.dependOn(&gen_step.step);

    b.installArtifact(sample_exe);

    const sample_run = b.addRunArtifact(sample_exe);
    sample_run.has_side_effects = true;
    const sample_run_step = b.step("run-sample", "Run the sample app");
    sample_run_step.dependOn(&sample_run.step);

    const flatbuffers_dep = b.dependency("flatbuffers", .{
        .target = target,
        .optimize = optimize,
    });

    const flatc = b.addExecutable(.{
        .name = "flatc",
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
    });
    //
    // This flatc build was created by running the following commands.  The resulting
    // build/compile_commands.json flags, includes and cpp files were used to
    // make this build file.
    //
    // $ mkdir build && cd build
    // $ cmake .. -DFLATBUFFERS_BUILD_FLATC=on -DFLATBUFFERS_BUILD_FLATLIB=off -DFLATBUFFERS_BUILD_TESTS=off -DFLATBUFFERS_BUILD_FLATHASH=off -DFLATBUFFERS_SKIP_MONSTER_EXTRA=on -DFLATBUFFERS_STRICT_MODE=on
    // $ cmake --build . -- -n > cmake_build_commands.txt
    //
    const cpp_flags = [_][]const u8{
        "-Wall",
        "-Werror",
        "-fno-rtti",
        // "-Wno-error=stringop-overflow",
        "-pedantic",
        "-Wextra",
        "-Wno-unused-parameter",
        "-Wold-style-cast",
        "-fsigned-char",
        "-Wnon-virtual-dtor",
        "-Wunused-result",
        "-Wunused-parameter",
        "-Werror=unused-parameter",
        "-Wmissing-declarations",
        "-Wzero-as-null-pointer-constant",
        "-faligned-new",
        // "-Werror=implicit-fallthrough=2",
        "-Wextra-semi",
    };

    const flatbuffers_files = [_][]const u8{
        "src/idl_parser.cpp",
        "src/idl_gen_text.cpp",
        "src/reflection.cpp",
        "src/util.cpp",
        "src/idl_gen_binary.cpp",
        "src/idl_gen_cpp.cpp",
        "src/idl_gen_csharp.cpp",
        "src/idl_gen_dart.cpp",
        "src/idl_gen_kotlin.cpp",
        "src/idl_gen_kotlin_kmp.cpp",
        "src/idl_gen_go.cpp",
        "src/idl_gen_java.cpp",
        "src/idl_gen_ts.cpp",
        "src/idl_gen_php.cpp",
        "src/idl_gen_python.cpp",
        "src/idl_gen_lobster.cpp",
        "src/idl_gen_rust.cpp",
        "src/idl_gen_fbs.cpp",
        "src/idl_gen_grpc.cpp",
        "src/idl_gen_json_schema.cpp",
        "src/idl_gen_swift.cpp",
        "src/file_name_saving_file_manager.cpp",
        "src/file_binary_writer.cpp",
        "src/file_writer.cpp",
        "src/flatc.cpp",
        "src/flatc_main.cpp",
        "src/binary_annotator.cpp",
        "src/annotated_binary_text_gen.cpp",
        "src/bfbs_gen_lua.cpp",
        "src/bfbs_gen_nim.cpp",
        "src/code_generators.cpp",
        "grpc/src/compiler/cpp_generator.cc",
        "grpc/src/compiler/go_generator.cc",
        "grpc/src/compiler/java_generator.cc",
        "grpc/src/compiler/python_generator.cc",
        "grpc/src/compiler/swift_generator.cc",
        "grpc/src/compiler/ts_generator.cc",
    };
    for (&flatbuffers_files) |file| {
        flatc.addCSourceFile(.{ .file = flatbuffers_dep.path(file), .flags = &cpp_flags });
    }
    for ([_][]const u8{ "include", "grpc" }) |include_path|
        flatc.addIncludePath(flatbuffers_dep.path(include_path));
    flatc.linkLibCpp();
    b.installArtifact(flatc);

    build_options.addOptionArtifact("flatc_exe_path", flatc);
    exe.step.dependOn(&flatc.step);

    const flatc_run = b.addRunArtifact(flatc);
    flatc_run.has_side_effects = true;
    flatc_run.cwd = b.path(".");
    if (b.args) |args| flatc_run.addArgs(args);
    const flatc_run_step = b.step("flatc", "Run packaged flatc compiler");
    flatc_run_step.dependOn(&flatc_run.step);
}
