:warning: This project is in its early early stages. Beware of bugs and missing features. :warning:

# About

Generate zig code from flatbuffer schema files which can de/serialize flatbuffer messages. Depends on packaged flatc to parse .fbs files.

CI tested weekly with latest zig version.

This project depends on packaged `flatc` compiler @v23.3.3, built with zig using [a fork of google/flatbuffers](https://github.com/travisstaloch/flatbuffers).

# Gen Steps
To auto generate code from a flatbuffers file in your build.zig see the example in [#18](https://github.com/travisstaloch/flatbufferz/pull/18).


# Usage

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

You can now import these files into your zig application.  The compiled .fb.zig
files depend on a "flatbufferz" module which can be provided by running:
```console
zig fetch --save=flatbufferz https://github.com/travisstaloch/flatbufferz/archive/be8fc9bfdfe416fe5b2ce24ed8f0e16700c103fb.tar.gz
```

That will add a dependency to your build.zig.zon:
```zig
// build.zig.zon
.{
    .name = "my-app",
    .version = "0.0.1",

    .dependencies = .{
        .flatbufferz = .{
            // note: you may need to change this url commit hash
            .url = "https://github.com/travisstaloch/flatbufferz/archive/be8fc9bfdfe416fe5b2ce24ed8f0e16700c103fb.tar.gz",
        },
    }
}

```

To add flatbufferz to a manually generated module.
```zig
// build.zig
const flatbufferz_dep = b.dependency("flatbufferz", .{
    .target = target,
    .optimize = optimize,
});
const flatbufferz_mod = flatbufferz_dep.module("flatbufferz");
const my_generated_mod = b.createModule(.{
    .root_source_file = b.path("src/my_generated.fb.zig"),
    .imports = &.{.{ .name = "flatbufferz", .module = flatbufferz_mod }},
});
```

To automatically generate code from a flatbuffers file [gen-steps](#gen-steps)

# Tools
Convert .bfbs to .fbs.
```console
zig-out/bin/flatc-zig gen/test.bfbs --bfbs-to-fbs
```
:warning: warning: --bfbs-to-fbs doesn't produce valid .fbs files. In its current state, it is more of a binary schema debugging tool. 