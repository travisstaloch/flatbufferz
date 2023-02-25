const Namer = @import("Namer.zig");
const idl = @import("idl.zig");

// This is a temporary helper function for code generators to call until all
// flag-overriding logic into flatc.cpp
pub fn withFlagOptions(
    input: Namer.Config,
    opts: idl.Options,
    path: []const u8,
) Namer.Config {
    var result = input;
    result.object_prefix = opts.object_prefix;
    result.object_suffix = opts.object_suffix;
    result.output_path = path;
    result.filename_suffix = opts.filename_suffix;
    return result;
}
