# args should be folders to be generated. usually examples/
# usage example: $ script/gen-all.sh -I examples examples/

set -e
ZIG_FLAGS= #
zig build $ZIG_FLAGS -freference-trace
DEST_DIR=gen

rm -rf gen/*

# iterate args, skipping '-I examples'
state="start"
inc=""
for arg in $@; do
  if [[ $arg == "-I" ]]; then
    state="-I"
  elif [[ $state == "-I" ]]; then
    state=""
    inc="$inc -I $arg"
  else
    FILES=$(find $arg -name "*.fbs")
    for file in $FILES; do
      script/gen.sh $inc $file      
    done
  fi
done
