# parse monster_test.fbs
# zig build run -Dlog-level=debug -freference-trace -- -z -I ~/Downloads/flatbuffers/tests/include_test ~/Downloads/flatbuffers/tests/monster_test.fbs -o gen\\a\\b\\c

# generate samples/monster_test.bfbs with comments and builtins
flatc -b --schema --bfbs-comments --bfbs-builtins --bfbs-gen-embed -o samples -I ~/Downloads/flatbuffers/tests/include_test ~/Downloads/flatbuffers/tests/monster_test.fbs

# convert examples/test.fbs to .bfbs with flatc and then back to .fbs using flatc-zig
flatc -b --schema --bfbs-comments --bfbs-builtins --bfbs-gen-embed -o gen -I examples examples/test.fbs && zig build && zig-out/bin/flatc-zig -o gen gen/test.bfbs --bfbs-to-fbs
