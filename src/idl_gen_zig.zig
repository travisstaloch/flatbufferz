const idl = @import("idl.zig");
const code_generator = @import("code_generator.zig");

pub fn init() code_generator.CodeGenerator {
    return .{ .language = .zig };
}
