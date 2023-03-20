:warning: This project is in its early early stages. expect bugs and missing features. :warning:

# About

Generate zig code from flatbuffer schema files which can de/serialize flatbuffer messages. Depends on packaged flatc to parse .fbs files.

Developed against zig version `0.11.0-dev.1987+a2c6ecd6d`

# Usage

Currently this project packages `flatc` in src/deps and thus depends on system installed cmake and c++ compiler.  It is planned to remove these dependencies and use zig to build the flatc compiler once the zig package manager gains better support for this.

```console
zig build
```

Optionally run tests
```console
zig build test
```

### compile from .fbs files
Use `flatc-zig` to generate zig files from schema (.fbs) files:
```console
zig-out/bin/flatc-zig -o gen -I examples/includes examples/test.fbs
```

### compile from .bfbs files
Optionally use `flatc` to generate a binary schema (.bfbs) from a schema (.fbs) files:
```console
src/deps/google-flatbuffers/build/flatc -b --schema --bfbs-comments --bfbs-builtins --bfbs-gen-embed -I examples/includes -o gen/examples examples/test.fbs
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

You can now import these files into your zig application.  The compiled .fb.zig
files depend on a "flatbufferz" module which can be provided by:
```zig
// build.zig.zon
.{
    .name = "my-app",
    .version = "0.0.1",

    .dependencies = .{
        .flatbufferz = .{
            // note: you may need to change this url commit hash
            .url = "https://github.com/travisstaloch/flatbufferz/archive/bf3c1f32abc977bdb73e1ddc153500f6c866914f.tar.gz",
        },
    }
}

```

```zig
// build.zig
const flatbufferz_dep = b.dependency("flatbufferz", .{
    .target = target,
    .optimize = optimize,
});
const flatbufferz_mod = flatbufferz_dep.module("flatbufferz");
my_exe.addModule("flatbufferz", flatbufferz_mod);
```

# Tools
Convert .bfbs to .fbs
```console
zig-out/bin/flatc-zig -o gen gen/test.bfbs --bfbs-to-fbs
```
