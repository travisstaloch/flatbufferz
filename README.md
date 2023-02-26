# About

Generate zig code from flatbuffer schema files which can de/serialize flatbuffer messages. Depends on flatc to parse .fbs files.

# Usage

First install `flatc`:
```console
sudo apt install flatbuffers-compiler
```
or [download a release](https://github.com/google/flatbuffers/releases)

Once you have `flatc` in your `$PATH`
```console
zig build
```

Optionally run tests
```console
zig build test
```

Use `flatc` to generate a binary schema (.bfbs) from your schema (.fbs):
```console
flatc -b --schema --bfbs-comments --bfbs-builtins -o gen -I examples examples/test.fbs
```
Use `flatc-zig` to generate zig files from a generated binary schema (.bfbs):
```console
# TODO
zig-out/bin/flatc-zig -o gen gen/test.bfbs
```
This creates the following in gen/
```console
# TODO
ls gen
test.fb.zig
```

# Tools
 Convert .bfbs to .fbs
 ```console
 zig-out/bin/flatc-zig -o gen gen/test.bfbs --bfbs-to-fbs
 ```
