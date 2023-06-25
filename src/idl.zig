const reflection = @import("flatbufferz").reflection;
const BaseType = reflection.BaseType;
pub fn isStruct(b: BaseType) bool {
    return b == .Obj;
}
pub fn isEnum(b: BaseType) bool {
    return b == .UType or b == .Union;
}
pub fn isVector(b: BaseType) bool {
    return b == .Vector;
}
pub fn isUnion(b: BaseType) bool {
    return b == .Union;
}
// pub fn isArray(b: BaseType) bool {
//     return b == .ARRAY;
// }

pub fn isScalar(t: BaseType) bool {
    return @intFromEnum(BaseType.UType) <= @intFromEnum(t) and
        @intFromEnum(t) <= @intFromEnum(BaseType.Double);
}
pub fn isInteger(t: BaseType) bool {
    return @intFromEnum(BaseType.UType) <= @intFromEnum(t) and
        @intFromEnum(t) <= @intFromEnum(BaseType.ULong);
}
pub fn isFloat(t: BaseType) bool {
    return t == .Float or t == .Double;
}
pub fn isLong(t: BaseType) bool {
    return t == .Long or t == .ULong;
}
pub fn isBool(t: BaseType) bool {
    return t == .Bool;
}
pub fn isOneByte(t: BaseType) bool {
    return @intFromEnum(BaseType.UType) <= @intFromEnum(t) and
        @intFromEnum(t) <= @intFromEnum(BaseType.Uchar);
}
