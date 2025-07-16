pub const Builder = @import("Builder.zig");
pub const Table = @import("Table.zig");
pub const Struct = Table.Struct;
pub const encode = @import("encode.zig");
pub const common = @import("common.zig");
pub const idl = @import("idl.zig");
pub const reflection = @import("reflection/lib.zig");
pub const binary_tools = @import("binary_tools.zig");
pub const codegen = @import("codegen.zig");
pub const util = @import("util.zig");

const fb = @import("flatbuffers.zig");

pub const GetRootAs = fb.GetRootAs;
pub const GetSizePrefixedRootAs = fb.GetSizePrefixedRootAs;
pub const GetSizePrefix = fb.GetSizePrefix;
pub const GetIndirectOffset = fb.GetIndirectOffset;
pub const GetBufferIdentifier = fb.GetBufferIdentifier;
pub const BufferHasIdentifier = fb.BufferHasIdentifier;
