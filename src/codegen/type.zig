const std = @import("std");
const refl = @import("flatbufferz").reflection;
const log = @import("types.zig").log;

fn ToType(comptime base_type: refl.BaseType) type {
    return switch (base_type) {
        .None => void,
        .Bool => bool,
        .Byte => i8,
        .UByte => u8,
        .Short => i16,
        .UShort => u16,
        .Int => i32,
        .UInt => u32,
        .Long => i64,
        .ULong => u64,
        .Float => f32,
        .Double => f64,
        .String => []const u8,
        else => |t| {
            @compileError(std.fmt.comptimePrint("invalid base type {any}", .{t}));
        },
    };
}

fn scalarName(base_type: refl.BaseType) []const u8 {
    return switch (base_type) {
        inline else => |t| std.fmt.comptimePrint("{}", .{ToType(t)}),
        .UType, .Vector, .Obj, .Union, .Array => |t| {
            log.err("invalid scalar type {any}", .{t});
            return "invalid scalar";
        },
    };
}

fn isBaseScalar(base_type: refl.BaseType) bool {
    return switch (base_type) {
        .None, .Bool, .Byte, .UByte, .Short, .UShort, .Int, .UInt, .Long, .ULong, .Float, .Double, .String => true,
        else => false,
    };
}

pub const Child = union(enum) {
    scalar: refl.BaseType,
    enum_: refl.Enum,
    object_: refl.Object,

    const Self = @This();
    const Tag = std.meta.Tag(Self);

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .scalar => |s| scalarName(s),
            inline else => |o| o.Name(),
        };
    }

    pub fn declarationFile(self: Self) []const u8 {
        return switch (self) {
            .scalar => "",
            inline else => |o| o.DeclarationFile(),
        };
    }

    pub fn type_(self: Self) Type {
        return switch (self) {
            .scalar => |s| Type{
                .base_type = s,
                .index = 0,
            },
            .enum_ => |e| Type.init(e.UnderlyingType().?),
            .object_ => Type{
                .base_type = .Obj,
                .index = 0,
            },
        };
    }

    pub fn isStruct(self: Self) bool {
        return switch (self) {
            .object_ => |o| o.IsStruct(),
            else => false,
        };
    }
};

// More closely matches a zig type and has convienence methods.
pub const Type = struct {
    base_type: refl.BaseType,
    element: refl.BaseType = .None,
    index: u32,
    fixed_len: u16 = 0,
    base_size: u32 = 4,
    element_size: u32 = 0,
    // These allow for a recursive `CodeWriter.getType`
    is_optional: bool = false,
    is_packed: bool = false,

    const Self = @This();

    pub fn init(ty: refl.Type) Self {
        return .{
            .base_type = ty.BaseType(),
            .element = ty.Element(),
            .index = @bitCast(u32, ty.Index()),
            .fixed_len = ty.FixedLength(),
            .base_size = ty.BaseSize(),
            .element_size = ty.ElementSize(),
        };
    }

    pub fn initFromField(field: refl.Field) Self {
        var res = init(field.Type().?);
        res.is_optional = field.Optional();
        return res;
    }

    pub fn isScalar(self: Self) bool {
        return isBaseScalar(self.base_type);
    }

    pub fn child(self: Self, schema: refl.Schema) ?Child {
        switch (self.base_type) {
            .Array, .Vector => {
                if (isBaseScalar(self.element)) return Child{ .scalar = self.element };
                const next_type = Self{ .base_type = self.element, .index = self.index, .is_packed = self.is_packed };
                return next_type.child(schema);
            },
            .Obj => {
                if (schema.Objects(self.index)) |obj| return Child{ .object_ = obj };
            },
            .UType, .Union => {
                if (schema.Enums(self.index)) |e| return Child{ .enum_ = e };
            },
            .Byte, .UByte, .Short, .UShort, .Int, .UInt, .Long, .ULong => {
                // Sometimes integer types are disguised as enums
                if (self.index < schema.EnumsLen()) {
                    if (schema.Enums(self.index)) |e| return Child{ .enum_ = e };
                }
            },
            else => {},
        }
        return null;
    }

    pub fn name(self: Self) []const u8 {
        return scalarName(self.base_type);
    }

    pub fn size(self: Self, schema: refl.Schema) !usize {
        if (self.element_size > 0) return self.element_size;

        return switch (self.base_type) {
            inline else => |t| @sizeOf(ToType(t)),
            .Vector, .Union, .Array, .Obj => self.child(schema).?.type_().size(schema),
            .UType => |t| {
                log.err("invalid scalar type {any}", .{t});
                return error.NoSize;
            },
        };
    }
};
