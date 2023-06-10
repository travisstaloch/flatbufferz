pub const Builder = @import("Builder.zig");
pub const Table = @import("Table.zig");
pub const Struct = Table.Struct;
pub const encode = @import("encode.zig");
pub const common = @import("common.zig");
pub const idl = @import("idl.zig");
pub const reflection = @import("reflection/lib.zig");
pub const binary_tools = @import("binary_tools.zig");
pub const codegen = @import("codegen/lib.zig");
pub const util = @import("util.zig");

pub usingnamespace @import("flatbuffers.zig");
