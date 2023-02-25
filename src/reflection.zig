pub usingnamespace @import("reflection_generated.zig");
pub const union_type_field_suffix = "_type";
const fb = @import("flatbuffers");
const Table = fb.Table;
const refl = @This();
const idl = @import("idl.zig");

/// New schema language features that are not supported by old code generators.
pub const AdvancedFeatures = enum(u4) {
    AdvancedArrayFeatures = 1,
    AdvancedUnionFeatures = 2,
    OptionalScalars = 4,
    DefaultVectorsAndStrings = 8,

    pub fn int(e: AdvancedFeatures) u4 {
        return @enumToInt(e);
    }
};

pub const KeyValue = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Key = Table.String(@This(), 4, .required);
    pub const Value = Table.String(@This(), 6, .{ .optional = "" });
};

pub const EnumVal = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const Value = Table.ReadWithDefault(@This(), i32, 6, .{ .optional = 0 });
    pub const UnionType = fb.Table.ReadStructIndirect(@This(), refl.Type, 10);
    pub const AttributesLen = Table.VectorLen(@This(), 12);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 12, null);
    pub const DocumentationLen = Table.VectorLen(@This(), 14);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 14, null);
    pub const DeclarationFile = Table.String(@This(), 16, .{ .optional = "" });
};

pub const Enum = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const ValuesLen = Table.VectorLen(@This(), 6);
    pub const Values = Table.VectorAt(@This(), EnumVal, 6, null);
    pub const IsUnion = fb.Table.ReadWithDefault(@This(), bool, 8, .{ .optional = false });
    pub const UnderlyingType = fb.Table.ReadStructIndirect(@This(), refl.Type, 10);
    pub const AttributesLen = Table.VectorLen(@This(), 12);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 12, null);
    pub const DocumentationLen = Table.VectorLen(@This(), 14);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 14, null);
    pub const DeclarationFile = Table.String(@This(), 16, .{ .optional = "" });
};

pub const Type = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const BaseType = Table.ReadWithDefault(@This(), idl.BaseType, 4, .required);
    pub const Element = Table.ReadWithDefault(@This(), idl.BaseType, 6, .{ .optional = .NONE });
    pub const Index = fb.Table.ReadWithDefault(@This(), i32, 8, -1);
    pub const FixedLength = fb.Table.ReadWithDefault(@This(), u16, 10, 0);
    pub const BaseSize = fb.Table.ReadWithDefault(@This(), u32, 12, 4);
    pub const ElementSize = fb.Table.ReadWithDefault(@This(), u32, 14, 0);
};

pub const Field = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const Type = fb.Table.ReadStructIndirect(@This(), refl.Type, 6);
    pub const Id = fb.Table.ReadWithDefault(@This(), u16, 8, 0);
    pub const Offset = fb.Table.ReadWithDefault(@This(), u16, 10, .{ .optional = 0 });
    pub const DefaultInteger = fb.Table.ReadWithDefault(@This(), u32, 12, .{ .optional = 0 });
    pub const DefaultReal = fb.Table.ReadWithDefault(@This(), f64, 14, .{ .optional = 0 });
    pub const Deprecated = fb.Table.ReadWithDefault(@This(), bool, 16, .{ .optional = false });
    pub const Required = fb.Table.ReadWithDefault(@This(), bool, 18, .{ .optional = false });
    pub const Key = fb.Table.ReadWithDefault(@This(), bool, 20, .{ .optional = false });
    pub const AttributesLen = Table.VectorLen(@This(), 22);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 22, null);
    pub const DocumentationLen = Table.VectorLen(@This(), 24);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 24, null);
    pub const Optional = fb.Table.ReadWithDefault(@This(), bool, 26, .{ .optional = false });
    pub const Padding = fb.Table.ReadWithDefault(@This(), u16, 28, 0);
};

pub const Object = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const IsStruct = fb.Table.ReadWithDefault(@This(), bool, 8, .{ .optional = false });
    pub const FieldsLen = Table.VectorLen(@This(), 6);
    pub const Fields = Table.VectorAt(@This(), Field, 6, null);
    pub const Minalign = fb.Table.ReadWithDefault(@This(), i32, 10, 0);
    pub const Bytesize = fb.Table.ReadWithDefault(@This(), i32, 12, .{ .optional = 0 });
    pub const AttributesLen = Table.VectorLen(@This(), 14);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 14, null);
    pub const DocumentationLen = Table.VectorLen(@This(), 16);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 16, null);
    pub const DeclarationFile = Table.String(@This(), 18, .{ .optional = "" });
};

pub const Schema = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const ObjectsLen = Table.VectorLen(@This(), 4);
    pub const Objects = Table.VectorAt(@This(), Object, 4, null);
    pub const EnumsLen = Table.VectorLen(@This(), 6);
    pub const Enums = Table.VectorAt(@This(), Enum, 6, null);
    pub const FileIdent = Table.String(@This(), 8, .{ .optional = "" });
    pub const FileExt = Table.String(@This(), 10, .{ .optional = "" });
    pub const RootObject = Table.ReadStructIndirect(@This(), Object, 12);
    pub const AdvancedFeatures = Table.ReadWithDefault(@This(), refl.AdvancedFeatures, 14, 0);
    pub const FbsFilesLen = Table.VectorLen(@This(), 16);
    pub const FbsFiles = Table.VectorAt(@This(), []const u8, 16, null);
};
