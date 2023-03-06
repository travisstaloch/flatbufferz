pub const BaseType = enum(u8) {
    NONE = 0,
    UTYPE = 1,
    BOOL = 2,
    CHAR = 3,
    UCHAR = 4,
    SHORT = 5,
    USHORT = 6,
    INT = 7,
    UINT = 8,
    LONG = 9,
    ULONG = 10,
    FLOAT = 11,
    DOUBLE = 12,
    STRING = 13,
    VECTOR = 14,
    STRUCT = 15,
    UNION = 16,
    ARRAY = 17,

    pub fn isStruct(b: BaseType) bool {
        return b == .STRUCT;
    }
    pub fn isEnum(b: BaseType) bool {
        return b == .UTYPE or b == .UNION;
    }
    pub fn isVector(b: BaseType) bool {
        return b == .VECTOR;
    }
    pub fn isUnion(b: BaseType) bool {
        return b == .UNION;
    }
    // pub fn isArray(b: BaseType) bool {
    //     return b == .ARRAY;
    // }

    pub fn isScalar(t: BaseType) bool {
        return @enumToInt(BaseType.UTYPE) <= @enumToInt(t) and
            @enumToInt(t) <= @enumToInt(BaseType.DOUBLE);
    }
    pub fn isInteger(t: BaseType) bool {
        return @enumToInt(BaseType.UTYPE) <= @enumToInt(t) and
            @enumToInt(t) <= @enumToInt(BaseType.ULONG);
    }
    pub fn isFloat(t: BaseType) bool {
        return t == .FLOAT or t == .DOUBLE;
    }
    pub fn isLong(t: BaseType) bool {
        return t == .LONG or t == .ULONG;
    }
    pub fn isBool(t: BaseType) bool {
        return t == .BOOL;
    }
    pub fn isOneByte(t: BaseType) bool {
        return @enumToInt(BaseType.UTYPE) <= @enumToInt(t) and
            @enumToInt(t) <= @enumToInt(BaseType.UCHAR);
    }
};
