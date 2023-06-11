const std = @import("std");
const fb = @import("flatbufferz");

pub const Allocator = std.mem.Allocator;
pub const refl = fb.reflection;
pub const Schema = refl.Schema;
pub const Enum = refl.Enum;
pub const EnumVal = refl.EnumVal;
pub const Object = refl.Object;
pub const Field = refl.Field;
pub const BaseType = refl.BaseType;
pub const Type = refl.Type;
pub const TypeT = struct {
    base_type: BaseType,
    element: BaseType = .None,
    index: i32 = -1,
    fixed_len: u16 = 0,
    base_size: u32 = 4,
    element_size: u32 = 0,
    // These allow for a recursive `CodeWriter.writeType`
    is_optional: bool = false,
    is_packed: bool = false,

    pub fn init(ty: Type) @This() {
        return .{
            .base_type = ty.BaseType(),
            .element = ty.Element(),
            .index = ty.Index(),
            .fixed_len = ty.FixedLength(),
            .base_size = ty.BaseSize(),
            .element_size = ty.ElementSize(),
        };
    }
};
pub const util = fb.util;
pub const common = fb.common;
pub const todo = common.todo;
pub const getFieldIdxById = util.getFieldIdxById;
pub const TypenameSet = std.StringHashMap(BaseType);
pub const log = std.log;

pub const Options = struct {
    write_index: bool,
    extension: []const u8,
    gen_path: []const u8,
};

pub const Prelude = struct {
    bfbs_path: []const u8,
    filename_noext: []const u8,
    file_ident: []const u8,
};

// fn writeSnakeCase(writer: anytype, word: []const u8) !void {
//     for (word, 0..) |c, i| {
//         switch (c) {
//             'a'...'z', '0'...'9' => try writer.writeByte(c),
//             'A'...'Z' => {
//                 if (i > 0 and std.ascii.isLower(c)) try writer.writeByte('_');
//                 try writer.writeByte(std.ascii.toLower(c));
//             },
//             '-' => try writer.writeByte('_'),
//             else => try writer.writeByte(c),
//         }
//     }
// }
