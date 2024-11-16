:warning: This project is in its early early stages. Beware of bugs and missing features. :warning:

# About

Generate zig code from flatbuffer schema files which can de/serialize flatbuffer messages. Depends on packaged flatc to parse .fbs files.

CI tested weekly with latest zig version.

This project depends on packaged `flatc` compiler @v23.3.3, built with zig using [a fork of google/flatbuffers](https://github.com/travisstaloch/flatbuffers).

# Usage

## Fetch
To generate code from a flatbuffers file in your build.zig:

```console
$ zig fetch --save git+https://github.com/travisstaloch/flatbufferz
```

## Gen Step
```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const fbz_dep = b.dependency("flatbufferz", .{
        .target = target,
        .optimize = optimize,
    });
    const gen_step = try @import("flatbufferz").GenStep.create(
        b,
        fbz_dep.artifact("flatc-zig"),
        &.{"src/myschema.fbs"},
        &.{},
        "flatc-zig",
    );
    exe.root_module.addImport("generated", gen_step.module);
    exe.root_module.addImport("flatbufferz", fbz_dep.module("flatbufferz"));
}

```


## Manual Generation

Run packaged flatc
```console
zig build flatc -- <flatc args>
```

### compile from .fbs files
Use `flatc-zig` to generate zig files from schema (.fbs) files:
```console
zig-out/bin/flatc-zig -o gen -I examples/includes examples/test.fbs
```

### compile from .bfbs files
Optionally use packaged `flatc` to generate a binary schema (.bfbs) from a schema (.fbs) files:
```console
zig build flatc -- -b --schema --bfbs-comments --bfbs-builtins --bfbs-gen-embed -I examples/includes -o gen/examples examples/test.fbs
```
Use `flatc-zig` to generate zig files from binary schema (.bfbs) files:
```
zig-out/bin/flatc-zig -o gen gen/examples/test.bfbs
```

### use compiled zig files
Either of these create the following in gen/
```console
$ find gen/ -name "*.fb.zig"
gen/Race.fb.zig
gen/People/X.fb.zig
gen/People/Foo.fb.zig
gen/People/Person.fb.zig
```

You can now import these files into your zig application as in [gen-step](#gen-step).  The compiled .fb.zig files depend on the same "flatbufferz" module.

```zig
// build.zig
const flatbufferz_dep = b.dependency("flatbufferz", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("generated", b.createModule(.{
    .root_source_file = b.path("src/my_generated.fb.zig"),
    .imports = &.{.{ .name = "flatbufferz", .module = flatbufferz_dep.module("flatbufferz") }},
}));
```


# Tools
Convert .bfbs to .fbs.
```console
zig-out/bin/flatc-zig gen/test.bfbs --bfbs-to-fbs
```
:warning: warning: --bfbs-to-fbs doesn't produce valid .fbs files. In its current state, it is more of a binary schema debugging tool. 