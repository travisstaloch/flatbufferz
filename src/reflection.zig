pub const union_type_field_suffix = "_type";
const fb = @import("flatbufferz");
const Table = fb.Table;
const refl = @This();

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
    pub const UnionType = Table.ReadStructIndirect(@This(), refl.Type, 10);
    pub const DocumentationLen = Table.VectorLen(@This(), 12);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 12, null);
    pub const AttributesLen = Table.VectorLen(@This(), 14);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 14, null);
    pub const DeclarationFile = Table.String(@This(), 16, .{ .optional = "" });
};

pub const Enum = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const ValuesLen = Table.VectorLen(@This(), 6);
    pub const Values = Table.VectorAt(@This(), EnumVal, 6, null);
    pub const IsUnion = Table.ReadWithDefault(@This(), bool, 8, .{ .optional = false });
    pub const UnderlyingType = Table.ReadStructIndirect(@This(), refl.Type, 10);
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
    pub const BaseType = Table.ReadWithDefault(@This(), fb.idl.BaseType, 4, .{ .optional = .NONE });
    pub const Element = Table.ReadWithDefault(@This(), fb.idl.BaseType, 6, .{ .optional = .NONE });
    pub const Index = Table.ReadWithDefault(@This(), i32, 8, .{ .optional = -1 });
    pub const FixedLength = Table.ReadWithDefault(@This(), u16, 10, 0);
    pub const BaseSize = Table.ReadWithDefault(@This(), u32, 12, .{ .optional = 4 });
    pub const ElementSize = Table.ReadWithDefault(@This(), u32, 14, .{ .optional = 0 });
};

pub const Field = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const Type = Table.ReadStructIndirect(@This(), refl.Type, 6);
    pub const Id = Table.ReadWithDefault(@This(), u16, 8, .{ .optional = 0 });
    pub const Offset = Table.ReadWithDefault(@This(), u16, 10, .{ .optional = 0 });
    pub const DefaultInteger = Table.ReadWithDefault(@This(), i64, 12, .{ .optional = 0 });
    pub const HasDefaultInteger = Table.Has(@This(), 12);
    pub const DefaultReal = Table.ReadWithDefault(@This(), f64, 14, .{ .optional = 0 });
    pub const HasDefaultReal = Table.Has(@This(), 14);
    pub const Deprecated = Table.ReadWithDefault(@This(), bool, 16, .{ .optional = false });
    pub const Required = Table.ReadWithDefault(@This(), bool, 18, .{ .optional = false });
    pub const Key = Table.ReadWithDefault(@This(), bool, 20, .{ .optional = false });
    pub const AttributesLen = Table.VectorLen(@This(), 22);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 22, null);
    pub const DocumentationLen = Table.VectorLen(@This(), 24);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 24, null);
    pub const Optional = Table.ReadWithDefault(@This(), bool, 26, .{ .optional = false });
    pub const Padding = Table.ReadWithDefault(@This(), u16, 28, .{ .optional = 0 });
};

pub const Object = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Name = Table.ReadByteVec(@This(), 4, null);
    pub const IsStruct = Table.ReadWithDefault(@This(), bool, 8, .{ .optional = false });
    pub const FieldsLen = Table.VectorLen(@This(), 6);
    pub const Fields = Table.VectorAt(@This(), Field, 6, null);
    pub const Minalign = Table.ReadWithDefault(@This(), i32, 10, .{ .optional = 0 });
    pub const Bytesize = Table.ReadWithDefault(@This(), i32, 12, .{ .optional = 0 });
    pub const AttributesLen = Table.VectorLen(@This(), 14);
    pub const Attributes = Table.VectorAt(@This(), KeyValue, 14, null);
    pub const DocumentationLen = Table.VectorLen(@This(), 16);
    pub const Documentation = Table.VectorAt(@This(), []const u8, 16, null);
    pub const DeclarationFile = Table.String(@This(), 18, .{ .optional = "" });
};

pub const SchemaFile = struct {
    _tab: Table,
    pub const init = Table.Init(@This());
    pub const GetRootAs = Table.GetRootAs(@This());
    pub const Filename = Table.ReadByteVec(@This(), 4, null);
    pub const IndcludedFilenamesLen = Table.VectorLen(@This(), 6);
    pub const IndcludedFilenames = Table.VectorAt(@This(), []const u8, 6, null);
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
    pub const RootTable = Table.ReadStructIndirect(@This(), Object, 12);
    pub const AdvancedFeatures = Table.ReadWithDefault(@This(), refl.AdvancedFeatures, 14, 0);
    pub const FbsFilesLen = Table.VectorLen(@This(), 16);
    pub const FbsFiles = Table.VectorAt(@This(), SchemaFile, 16, null);
};
