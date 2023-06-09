# args: -I examples examples/file.fbs
# set -ex
DEST_DIR=gen
dir=${dir%/*}
CMD="zig-out/bin/flatc-zig -o gen $@"
echo $CMD
$($CMD)
