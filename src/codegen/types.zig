const std = @import("std");
const fb = @import("flatbufferz");

pub const refl = fb.reflection;
pub const Schema = refl.Schema;
pub const Enum = refl.Enum;
pub const EnumVal = refl.EnumVal;
pub const Object = refl.Object;
pub const Field = refl.Field;
pub const BaseType = refl.BaseType;
pub const Type = refl.Type;
pub const util = fb.util;
pub const common = fb.common;
pub const todo = common.todo;
pub const getFieldIdxById = util.getFieldIdxById;
pub const TypenameSet = std.StringHashMap(BaseType);
pub const log = std.log;

pub const Options = struct {
    extension: []const u8,
    lib_path: []const u8,
    gen_path: []const u8,
};

pub const Prelude = struct {
    bfbs_path: []const u8,
    filename_noext: []const u8,
    file_ident: []const u8,
};
