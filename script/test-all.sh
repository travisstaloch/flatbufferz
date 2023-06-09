zig build run-sample && zig build test && zig build && script/gen-all.sh -I examples -I examples/include_test -I examples/include_test/sub -I examples/includes examples/ 

for file in $(find gen -name "*.fb.zig"); do
  CMD="zig test $file --mod flatbufferz:flatbufferz:src/lib.zig  --deps flatbufferz -freference-trace --main-pkg-path gen"
  echo $CMD
  $($CMD)
done