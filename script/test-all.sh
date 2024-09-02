set -e

zig build run-sample
zig build test
zig build
script/gen-all.sh -I examples -I examples/include_test -I examples/include_test/sub -I examples/includes examples/

for file in $(find gen -name "*.fb.zig"); do
  CMD="zig test --dep flatbufferz -Mroot=$file --dep flatbufferz -Mflatbufferz=src/lib.zig -freference-trace"
  echo $CMD
  $($CMD)
done
