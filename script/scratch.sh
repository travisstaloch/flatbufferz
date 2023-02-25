# parse monster_test.fbs
# zig build run -Dlog-level=debug -freference-trace -- -z -I ~/Downloads/flatbuffers/tests/include_test ~/Downloads/flatbuffers/tests/monster_test.fbs -o gen\\a\\b\\c

# generate samples/monster_test.bfbs with comments and builtins
flatc -b --schema --bfbs-comments --bfbs-builtins -o samples -I ~/Downloads/flatbuffers/tests/include_test ~/Downloads/flatbuffers/tests/monster_test.fbs