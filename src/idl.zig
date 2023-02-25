const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const common = @import("common.zig");
const todo = common.todo;
const base = @import("base.zig");
const util = @import("util.zig");

pub const BaseType = enum(u5) {
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
    pub fn isScalar(t: BaseType) bool {
        return @enumToInt(t) >= @enumToInt(BaseType.UTYPE) and
            @enumToInt(t) <= @enumToInt(BaseType.DOUBLE);
    }
    pub fn isInteger(t: BaseType) bool {
        return @enumToInt(t) >= @enumToInt(BaseType.UTYPE) and
            @enumToInt(t) <= @enumToInt(BaseType.ULONG);
    }
    pub fn isFloat(t: BaseType) bool {
        return t == .FLOAT or
            t == .DOUBLE;
    }
    pub fn isLong(t: BaseType) bool {
        return t == .LONG or
            t == .ULONG;
    }
    pub fn isBool(t: BaseType) bool {
        return t == .BOOL;
    }
    pub fn isVector(t: BaseType) bool {
        return t == .VECTOR;
    }
    pub fn isString(t: BaseType) bool {
        return t == .STRING;
    }
    pub fn isArray(t: BaseType) bool {
        return t == .ARRAY;
    }
    pub fn isStruct(t: BaseType) bool {
        return t == .STRUCT;
    }
    pub fn isOneByte(t: BaseType) bool {
        return @enumToInt(t) >= @enumToInt(BaseType.UTYPE) and
            @enumToInt(t) <= @enumToInt(BaseType.UCHAR);
    }
    pub fn isUnsigned(t: BaseType) bool {
        return t == .UTYPE or t == .UCHAR or
            t == .USHORT or t == .UINT or
            t == .ULONG;
    }
    pub fn typeName(t: BaseType) []const u8 {
        return switch (t) {
            .NONE => "none",
            .UTYPE => "utype",
            .BOOL => "bool",
            .CHAR => "byte",
            .UCHAR => "ubyte",
            .SHORT => "short",
            .USHORT => "ushort",
            .INT => "int",
            .UINT => "uint",
            .LONG => "long",
            .ULONG => "ulong",
            .FLOAT => "float",
            .DOUBLE => "double",
            .STRING => "string",
            .VECTOR => "vector",
            .STRUCT => "struct",
            .UNION => "union",
            .ARRAY => "array",
        };
    }
    pub fn sizeOf(t: BaseType) u32 {
        return switch (t) {
            .NONE => @sizeOf(u8),
            .UTYPE => @sizeOf(u8),
            .BOOL => @sizeOf(u8),
            .CHAR => @sizeOf(i8),
            .UCHAR => @sizeOf(u8),
            .SHORT => @sizeOf(i16),
            .USHORT => @sizeOf(u16),
            .INT => @sizeOf(i32),
            .UINT => @sizeOf(u32),
            .LONG => @sizeOf(i64),
            .ULONG => @sizeOf(u64),
            .FLOAT => @sizeOf(f32),
            .DOUBLE => @sizeOf(f64),
            .STRING => todo("??", .{}), // @sizeOf(Offset(void)),
            .VECTOR => todo("??", .{}), // @sizeOf(Offset(void)),
            .STRUCT => todo("??", .{}), // @sizeOf(Offset(void)),
            .UNION => todo("??", .{}), //@sizeOf(Offset(void)),
            .ARRAY => todo("??", .{}), // @sizeOf(int),

        };
    }
};

pub const RPCCall = struct { //  : public Definition {
    base: Definition,
    // Offset<reflection::RPCCall> Serialize(FlatBufferBuilder *builder,
    //                                       const Parser &parser) const;

    // bool Deserialize(Parser &parser, const reflection::RPCCall *call);

    request: ?*StructDef = null,
    response: ?*StructDef = null,
};

pub const ServiceDef = struct { //  : public Definition {
    base: Definition,
    // Offset<reflection::Service> Serialize(FlatBufferBuilder *builder,
    //                                       const Parser &parser) const;
    // bool Deserialize(Parser &parser, const reflection::Service *service);

    calls: SymbolTable(RPCCall) = .{},
};

// This encapsulates where the parser is in the current source file.
pub const ParserState = struct {
    //  ParserState()
    //      : prev_cursor_(null),
    //        cursor_(null),
    //        line_start_(null),
    //        line_(0),
    //        token_(-1),
    //        attr_is_trivial_ascii_string_(true) {}

    // protected:
    pub fn resetState(s: *ParserState, source: []const u8) void {
        s.prev_cursor_ = source.ptr;
        s.cursor_ = source.ptr;
        s.line_ = 0;
        s.markNewLine();
    }

    pub fn markNewLine(s: *ParserState) void {
        s.line_start_ = s.cursor_;
        s.line_ += 1;
    }

    pub fn cursorPosition(s: ParserState) i64 {
        // FLATBUFFERS_ASSERT(cursor_ && line_start_ && cursor_ >= line_start_);
        assert(@ptrToInt(s.cursor_) >= @ptrToInt(s.line_start_));
        return @intCast(i64, @ptrToInt(s.cursor_) - @ptrToInt(s.line_start_));
    }

    prev_cursor_: [*]const u8 = undefined,
    cursor_: [*]const u8 = undefined,
    line_start_: [*]const u8 = undefined,
    line_: i32 = 0, // the current line being parsed
    token_: i32 = -1,

    // Flag: text in attribute_ is true ASCII string without escape
    // sequences. Only printable ASCII (without [\t\r\n]).
    // Used for number-in-string (and base64 string in future).
    attr_is_trivial_ascii_string_: bool = true,
    attribute_: std.ArrayListUnmanaged(u8) = .{},
    doc_comment_: std.ArrayListUnmanaged([]const u8) = .{},
};

pub const Options = struct {
    // field case style options for C++
    pub const CaseStyle = enum { unchanged, upper, lower };
    pub const ProtoIdGapAction = enum { NO_OP, WARNING, ERROR };
    // gen_jvmstatic: bool = false,
    /// Use flexbuffers instead for binary and text generation
    use_flexbuffers: bool = false,
    // strict_json: bool = false,
    // output_default_scalars_in_json: bool = false,
    // indent_step: i32 ,
    // cpp_minify_enums: bool = false,
    // output_enum_identifiers: bool = false,
    // prefixed_enums: bool = false,
    // scoped_enums: bool = false,
    // emit_min_max_enum_values: bool = false,
    // swift_implementation_only: bool = false,
    // include_dependence_headers: bool = false,
    // mutable_buffer: bool = false,
    // one_file: bool = false,
    proto_mode: bool = false,
    // proto_oneof_union: bool = false,
    generate_all: bool = false,
    // skip_unexpected_fields_in_json: bool = false,
    // generate_name_strings: bool = false,
    // generate_object_based_api: bool = false,
    // gen_compare: bool = false,
    // cpp_object_api_pointer_type: []const u8 ,
    // cpp_object_api_string_type: []const u8 ,
    // cpp_object_api_string_flexible_constructor: bool = false,
    // cpp_object_api_field_case_style: CaseStyle ,
    // cpp_direct_copy: bool = false,
    // gen_nullable: bool = false,
    // java_checkerframework: bool = false,
    // gen_generated: bool = false,
    // gen_json_coders: bool = false,
    object_prefix: []const u8 = "",
    object_suffix: []const u8 = "",
    union_value_namespacing: bool = true,
    allow_non_utf8: bool = false,
    // natural_utf8: bool = false,
    // include_prefix: []const u8 ,
    // keep_prefix: bool = false,
    binary_schema_comments: bool = false,
    // binary_schema_builtins: bool = false,
    // binary_schema_gen_embed: bool = false,
    // go_import: []const u8 ,
    // go_namespace: []const u8 ,
    // go_module_name: []const u8 ,
    // protobuf_ascii_alike: bool = false,
    // size_prefixed: bool = false,
    root_type: []const u8 = "",
    // force_defaults: bool = false,
    // java_primitive_has_method: bool = false,
    // cs_gen_json_serializer: bool = false,
    // cpp_includes: std.ArrayListUnmanaged([]const u8),
    // cpp_std: []const u8 ,
    // cpp_static_reflection: bool = false,
    // proto_namespace_suffix: []const u8 ,
    filename_suffix: []const u8 = "",
    // filename_extension: []const u8 ,
    no_warnings: bool = false,
    warnings_as_errors: bool = false,
    project_root: []const u8 = "",
    // cs_global_alias: bool = false,
    // json_nested_flatbuffers: bool = false,
    // json_nested_flexbuffers: bool = false,
    // json_nested_legacy_flatbuffers: bool = false,
    // ts_flat_files: bool = false,
    // ts_entry_points: bool = false,
    // ts_no_import_ext: bool = false,
    no_leak_private_annotations: bool = false,
    // require_json_eof: bool = false,
    // keep_proto_id: bool = false,
    // proto_id_gap_action: ProtoIdGapAction ,
    lang_to_generate: std.enums.EnumSet(Language) =
        std.enums.EnumSet(Language).initEmpty(),

    // enum MiniReflect { kNone, kTypes, kTypesAndNames };
    // MiniReflect mini_reflect;
    /// If set, require all fields in a table to be explicitly numbered.
    require_explicit_ids: bool = false,

    // // If set, implement serde::Serialize for generated Rust types
    // bool rust_serialize;
    // If set, generate zig types in individual files with a root module file.
    zig_module_root_file: bool = false,
    // // The corresponding language bit will be set if a language is included
    // // for code generation.
    // unsigned long lang_to_generate;
    // // If set (default behavior), empty string fields will be set to null to
    // // make the flatbuffer more compact.
    // bool set_empty_strings_to_null;
    // // If set (default behavior), empty vector fields will be set to null to
    // // make the flatbuffer more compact.
    // bool set_empty_vectors_to_null;

    // IDLOptions()
    //     : gen_jvmstatic(false),
    //       use_flexbuffers(false),
    //       strict_json(false),
    //       output_default_scalars_in_json(false),
    //       indent_step(2),
    //       cpp_minify_enums(false),
    //       output_enum_identifiers(true),
    //       prefixed_enums(true),
    //       scoped_enums(false),
    //       emit_min_max_enum_values(true),
    //       swift_implementation_only(false),
    //       include_dependence_headers(true),
    //       mutable_buffer(false),
    //       one_file(false),
    //       proto_mode(false),
    //       proto_oneof_union(false),
    //       generate_all(false),
    //       skip_unexpected_fields_in_json(false),
    //       generate_name_strings(false),
    //       generate_object_based_api(false),
    //       gen_compare(false),
    //       cpp_object_api_pointer_type("std::unique_ptr"),
    //       cpp_object_api_string_flexible_constructor(false),
    //       cpp_object_api_field_case_style(CaseStyle_Unchanged),
    //       cpp_direct_copy(true),
    //       gen_nullable(false),
    //       java_checkerframework(false),
    //       gen_generated(false),
    //       gen_json_coders(false),
    //       object_suffix("T"),
    //       union_value_namespacing(true),
    //       allow_non_utf8(false),
    //       natural_utf8(false),
    //       keep_prefix(false),
    //       binary_schema_comments(false),
    //       binary_schema_builtins(false),
    //       binary_schema_gen_embed(false),
    //       protobuf_ascii_alike(false),
    //       size_prefixed(false),
    //       force_defaults(false),
    //       java_primitive_has_method(false),
    //       cs_gen_json_serializer(false),
    //       cpp_static_reflection(false),
    //       filename_suffix("_generated"),
    //       filename_extension(),
    //       no_warnings(false),
    //       warnings_as_errors(false),
    //       project_root(""),
    //       cs_global_alias(false),
    //       json_nested_flatbuffers(true),
    //       json_nested_flexbuffers(true),
    //       json_nested_legacy_flatbuffers(false),
    //       ts_flat_files(false),
    //       ts_entry_points(false),
    //       ts_no_import_ext(false),
    //       no_leak_private_annotations(false),
    //       require_json_eof(true),
    //       keep_proto_id(false),
    //       proto_id_gap_action(ProtoIdGapAction::WARNING),
    //       mini_reflect(IDLOptions::kNone),
    //       require_explicit_ids(false),
    //       rust_serialize(false),
    //       rust_module_root_file(false),
    //       lang_to_generate(0),
    //       set_empty_strings_to_null(true),
    //       set_empty_vectors_to_null(true) {}
    pub const Language = enum {
        zig,
    };

    // Possible options for the more general generator below.
    // enum Language {
    //   kJava = 1 << 0,
    //   kCSharp = 1 << 1,
    //   kGo = 1 << 2,
    //   kCpp = 1 << 3,
    //   kPython = 1 << 5,
    //   kPhp = 1 << 6,
    //   kJson = 1 << 7,
    //   kBinary = 1 << 8,
    //   kTs = 1 << 9,
    //   kJsonSchema = 1 << 10,
    //   kDart = 1 << 11,
    //   kLua = 1 << 12,
    //   kLobster = 1 << 13,
    //   kRust = 1 << 14,
    //   kKotlin = 1 << 15,
    //   kSwift = 1 << 16,
    //   kNim = 1 << 17,
    //   kMAX
    // };

};

pub const IncludedFile = struct {
    schema_name: []const u8,
    filename: []const u8,

    pub const Ctx = struct {
        pub fn hash(_: Ctx, f: IncludedFile) u64 {
            return std.hash_map.hashString(f.filename);
        }
        pub fn eql(_: Ctx, a: IncludedFile, b: IncludedFile) bool {
            return mem.eql(u8, a.filename, b.filename);
        }
    };
};

/// Represents any type in the IDL, which is a combination of the BaseType
/// and additional information for vectors/structs_.
pub const Type = struct {
    // explicit Type(BaseType _base_type = BASE_TYPE_NONE, StructDef *_sd = null,
    //               EnumDef *_ed = null, u16 _fixed_length = 0)
    //     : base_type(_base_type),
    //       element(BASE_TYPE_NONE),
    //       struct_def(_sd),
    //       enum_def(_ed),
    //       fixed_length(_fixed_length) {}

    // bool operator==(const Type &o) const {
    //   return base_type == o.base_type && element == o.element &&
    //          struct_def == o.struct_def && enum_def == o.enum_def;
    // }

    // Type VectorType() const {
    //   return Type(element, struct_def, enum_def, fixed_length);
    // }

    // Offset(reflection):Type> Serialize(FlatBufferBuilder *builder) const;

    // bool Deserialize(const Parser &parser, const reflection::Type *type);

    base_type: BaseType = .NONE,
    element: BaseType = .NONE, // only set if t == BASE_TYPE_VECTOR
    struct_def: ?*StructDef = null, // only set if t or element == BASE_TYPE_STRUCT
    enum_def: ?*EnumDef = null, // set if t == BASE_TYPE_UNION / BASE_TYPE_UTYPE,
    //                         // or for an integral type derived from an enum.
    fixed_length: u16 = 0, // only set if t == BASE_TYPE_ARRAY

    pub fn init(
        base_type: BaseType,
        struct_def: ?*StructDef,
        enum_def: ?*EnumDef,
        fixed_length: u16,
    ) Type {
        return .{
            .base_type = base_type,
            .struct_def = struct_def,
            .enum_def = enum_def,
            .fixed_length = fixed_length,
        };
    }
    pub fn isString(ty: Type) bool {
        return ty.base_type == .STRING;
    }

    pub fn isStruct(ty: Type) bool {
        return ty.base_type == .STRUCT and ty.struct_def.?.fixed;
    }

    pub fn isIncompleteStruct(ty: Type) bool {
        return ty.base_type == .STRUCT and ty.struct_def.?.predecl;
    }

    pub fn isTable(ty: Type) bool {
        return ty.base_type == .STRUCT and !ty.struct_def.?.fixed;
    }

    pub fn isUnion(ty: Type) bool {
        return ty.enum_def != null and ty.enum_def.?.is_union;
    }

    pub fn isUnionType(ty: Type) bool {
        return ty.isUnion() and ty.base_type.isInteger();
    }

    pub fn isVector(ty: Type) bool {
        return ty.base_type == .VECTOR;
    }

    pub fn isVectorOfStruct(ty: Type) bool {
        return ty.isVector() and ty.vectorType().isStruct();
    }

    pub fn isVectorOfTable(ty: Type) bool {
        return ty.isVector() and ty.vectorType().isTable();
    }

    pub fn isArray(ty: Type) bool {
        return ty.base_type == .ARRAY;
    }

    pub fn isSeries(ty: Type) bool {
        return ty.isVector() or ty.isArray();
    }

    pub fn isEnum(ty: Type) bool {
        return ty.enum_def != null and ty.base_type.isInteger();
    }

    pub fn vectorType(ty: Type) Type {
        return Type.init(ty.element, ty.struct_def, ty.enum_def, ty.fixed_length);
    }

    pub fn inlineSize(ty: Type) usize {
        return if (ty.base_type.isStruct())
            ty.struct_def.?.bytesize
        else if (ty.base_type.isArray())
            ty.vectorType().inlineSize() * ty.fixed_length
        else
            ty.base_type.sizeOf();
    }

    pub inline fn inlineAlignment(ty: Type) usize {
        if (ty.base_type.isStruct()) {
            return ty.struct_def.?.minalign;
        } else if (ty.base_type.isArray()) {
            return if (ty.vectorType().base_type.isStruct())
                ty.struct_def.?.minalign
            else
                (ty.element.sizeOf());
        } else {
            return (ty.base_type.sizeOf());
        }
    }
};

/// Represents a parsed scalar value, it's type, and field offset.
pub const Value = struct {
    // Value()
    //     : constant("0"),
    //       offset(static_cast<voffset_t>(~(static_cast<voffset_t>(0U)))) {}
    type: Type,
    constant: []const u8 = "0",
    offset: u16 = ~@as(u16, 0),
};

/// Helper class that retains the original order of a set of identifiers and
/// also provides quick lookup.
pub fn SymbolTable(comptime T: type) type {
    return struct {
        const Self = @This();
        // public:
        // std::map<[]const u8, T *> dict;  // quick lookup
        dict: std.StringHashMapUnmanaged(*T) = .{},
        // std.ArrayListUnmanaged(T *> vec;             // Used to iterate in order of insert)n
        vec: std.ArrayListUnmanaged(*T) = .{},
        // public:
        //  ~SymbolTable() {
        //    for (auto it = vec.begin(); it != vec.end(); ++it) { delete *it; }
        //  }

        pub fn add(s: *Self, alloc: mem.Allocator, name: []const u8, e: *T) !bool {
            try s.vec.append(alloc, e);
            const gop = try s.dict.getOrPut(alloc, name);
            if (gop.found_existing) return true;
            gop.value_ptr.* = e;
            return false;
        }

        pub fn move(
            s: *Self,
            alloc: mem.Allocator,
            oldname: []const u8,
            newname: []const u8,
        ) !void {
            if (s.dict.get(oldname)) |it| {
                _ = s.dict.remove(oldname);
                try s.dict.put(alloc, newname, it);
            } else {
                assert(false);
            }
        }

        pub fn lookup(s: Self, name: []const u8) ?*T {
            // std.log.debug("{s}.lookup({s})", .{ @typeName(Self), name });
            // var iter = s.dict.iterator();
            // while (iter.next()) |it| std.log.debug("{s}", .{it.key_ptr.*});
            return s.dict.get(name);
        }
    };
}

/// A name space, as set in the schema.
pub const Namespace = struct {
    // Namespace() : from_table(0) {}

    components: std.ArrayListUnmanaged([]const u8) = .{},
    from_table: usize = 0, // Part of the namespace corresponds to a message/table.

    /// Given a (potentially unqualified) name, return the "fully qualified" name
    /// which has a full namespaced descriptor.
    /// With max_components you can request less than the number of components
    /// the current namespace has.
    pub fn getFullyQualifiedName(
        n: Namespace,
        alloc: mem.Allocator,
        name: []const u8,
        opts: struct { max_components: usize = 1000 },
    ) ![]const u8 {
        // std.log.debug("getFullyQualifiedName({s}, {s})", .{ n.components.items, name });
        // Early exit if we don't have a defined namespace.
        if (n.components.items.len == 0 or opts.max_components == 0) {
            return name;
        }
        var stream_str = std.ArrayList(u8).init(alloc);
        var i: usize = 0;
        while (i < @min(n.components.items.len, opts.max_components)) : (i += 1) {
            try stream_str.appendSlice(n.components.items[i]);
            try stream_str.append('.');
        }
        if (stream_str.items.len != 0) stream_str.items.len -= 1;
        if (name.len != 0) {
            try stream_str.append('.');
            try stream_str.appendSlice(name);
        }
        return stream_str.toOwnedSlice();
    }
};

// pub fn operator<type: Type, bool const Namespace &b) {
//   usize min_size = std::min(a.components.size(), b.components.size());
//   for (usize i = 0; i < min_size; ++i) {
//     if (a.components[i] != b.components[i])
//       return a.components[i] < b.components[i];
//   }
//   return a.components.size() < b.components.size();
// }

// // Base class for all definition types (fields, structs_, enums_).
pub const Definition = struct {
    // Definition()
    //     : generated(false),
    //       defined_namespace(null),
    //       serialized_location(0),
    //       index(-1),
    //       refcount(1),
    //       declaration_file(null) {}

    // flatbuffers::Offset()
    //     flatbuffers::Vector<flatbuffers::Offset(reflection):KeyValue>>>
    // SerializeAttributes(FlatBufferBuilder *builder, const Parser &parser) const;

    // bool DeserializeAttributes(Parser &parser,
    //                            const Vector<Offset(reflection):KeyValue>> *attrs);

    name: []const u8,
    file: []const u8,
    doc_comment: std.ArrayListUnmanaged([]const u8) = .{},
    attributes: SymbolTable(Value) = .{},
    generated: bool = false, // did we already output code for this definition?
    defined_namespace: ?*Namespace = null, // Where it was defined.

    // For use with Serialize()
    serialized_location: u32 = 0,
    index: i32 = -1, // Inside the vector it is stored.
    refcount: i32 = 1,
    declaration_file: []const u8 = "",
};

pub const FieldDef = struct { // : public Definition {
    // FieldDef()
    //     : deprecated(false),
    //       key(false),
    //       shared(false),
    //       native_inline(false),
    //       flexbuffer(false),
    //       presence(kDefault),
    //       nested_flatbuffer(null),
    //       padding(0),
    //       sibling_union_field(null) {}

    // Offset(reflection):Field> Serialize(FlatBufferBuilder *builder, u16 id,
    //                                     const Parser &parser) const;

    // bool Deserialize(Parser &parser, const reflection::Field *field);

    base: Definition,
    value: Value,
    deprecated: bool = false, // Field is allowed to be present in old data, but can't be.
    // written in new data nor accessed in new code.
    key: bool = false, // Field functions as a key for creating sorted vectors.
    shared: bool = false, // Field will be using string pooling (i.e. CreateSharedString)
    // as default serialization behavior if field is a string.
    native_inline: bool = false, // Field will be defined inline (instead of as a pointer)
    // for native tables if field is a struct.
    flexbuffer: bool = false, // This field contains FlexBuffer data.

    presence: Presence = .Default,

    nested_flatbuffer: ?*StructDef = null, // This field contains nested FlatBuffer data.
    padding: usize = 0, // Bytes to always pad after this field.

    // sibling_union_field is always set to null. The only exception is
    // when FieldDef is a union field or an union type field. Therefore,
    // sibling_union_field on a union field points to the union type field
    // and vice-versa.
    sibling_union_field: ?*FieldDef = null,

    pub const Presence = enum {
        // Field must always be present.
        Required,
        // Non-presence should be signalled to and controlled by users.
        Optional,
        // Non-presence is hidden from users.
        // Implementations may omit writing default values.
        Default,
    };
    // Presence static MakeFieldPresence(bool optional, bool required) {
    //   optional)): FLATBUFFERS_ASSERT(!(required && ,
    //   // clang-format off
    //   return required ? FieldDef::kRequired
    //        : optional ? FieldDef::kOptional
    //                   kDefault: : FieldDef::,
    //   // clang-format on
    // }

    pub fn makeFieldPresence(optional: bool, required: bool) Presence {
        assert(!(required and optional));
        // clang-format off
        return if (required)
            .Required
        else if (optional)
            .Optional
        else
            .Default;
        // clang-format on
    }

    pub fn isScalarOptional(f: FieldDef) bool {
        return f.value.type.base_type.isScalar() and f.isOptional();
    }
    pub fn isOptional(f: FieldDef) bool {
        return f.presence == .Optional;
    }
    // bool IsRequired() const { return presence == kRequired; }
    // bool IsDefault() const { return presence == kDefault; }

    // static bool compareFieldDefs(const FieldDef *a, const FieldDef *b) {
    //   auto a_id = atoi(a.attributes.Lookup("id").constant.c_str());
    //   auto b_id = atoi(b.attributes.Lookup("id").constant.c_str());
    //   return a_id < b_id;
    // }

};

pub const StructDef = struct { //  : public Definition {
    // StructDef()
    //     : fixed(false),
    //       predecl(true),
    //       sortbysize(true),
    //       has_key(false),
    //       minalign(1),
    //       bytesize(0) {}

    // Offset(reflection):Object> Serialize(FlatBufferBuilder *builder,
    //                                      const Parser &parser) const;

    // bool Deserialize(Parser &parser, const reflection::Object *object);
    base: Definition,
    fields: SymbolTable(FieldDef) = .{},

    fixed: bool = false, // If it's struct, not a table.
    predecl: bool = true, // If it's used before it was defined.
    sortbysize: bool = true, // Whether fields come in the declaration or size order.
    has_key: bool = false, // It has a key field.
    minalign: usize = 1, // What the whole object needs to be aligned to.
    bytesize: usize = 0, // Size if fixed.

    original_location: []const u8 = "",
    reserved_ids: std.ArrayListUnmanaged(u16) = .{},

    pub fn padLastField(s: *StructDef, min_align: usize) void {
        const padding = base.paddingBytes(s.bytesize, min_align);
        s.bytesize += padding;
        if (s.fields.vec.items.len > 0) s.fields.vec.getLast().padding = padding;
    }
};

pub const EnumVal = struct {
    value: i64,

    name: []const u8,
    doc_comment: std.ArrayListUnmanaged([]const u8) = .{},
    union_type: Type,
    attributes: SymbolTable(Value) = .{},

    // private:
    //  friend EnumDef;
    //  friend EnumValBuilder;
    //  friend bool operator==(const EnumVal &lhs, const EnumVal &rhs);

    //  EnumVal(const std::string &_name, int64_t _val) : name(_name), value(_val) {}
    //  EnumVal() : value(0) {}

    //  Offset<reflection::EnumVal> Serialize(FlatBufferBuilder *builder,
    //                                        const Parser &parser) const;

    //  bool Deserialize(Parser &parser, const reflection::EnumVal *val);

    //  flatbuffers::Offset<
    //      flatbuffers::Vector<flatbuffers::Offset<reflection::KeyValue>>>
    //  SerializeAttributes(FlatBufferBuilder *builder, const Parser &parser) const;

    //  bool DeserializeAttributes(Parser &parser,
    //                             const Vector<Offset<reflection::KeyValue>> *attrs);

    pub fn getAsUInt64(e: EnumVal) u64 {
        return @bitCast(u64, e.value);
    }
    pub fn getAsInt64(e: EnumVal) i64 {
        return e.value;
    }
    //  int64_t GetAsInt64() const { return value; }
    //  bool IsZero() const { return 0 == value; }
    //  bool IsNonZero() const { return !IsZero(); }

};

// struct EnumDef;
// struct EnumValBuilder;

// struct EnumVal {
//   Offset(reflection):EnumVal> Serialize(FlatBufferBuilder *builder,
//                                         const Parser &parser) const;

//   bool Deserialize(Parser &parser, const reflection::EnumVal *val);

//   flatbuffers::Offset()
//       flatbuffers::Vector<flatbuffers::Offset(reflection):KeyValue>>>
//   SerializeAttributes(FlatBufferBuilder *builder, const Parser &parser) const;

//   bool DeserializeAttributes(Parser &parser,
//                              const Vector<Offset(reflection):KeyValue>> *attrs);

//   u64 GetAsUInt64() const { return static_cast<u64>(value); }
//   i64 GetAsInt64() const { return value; }
//   bool IsZero() const { return 0 == value; }
//   bool IsNonZero() const { return !IsZero(); }

//   []const u8 name;
//   std.ArrayListUnmanaged([]const u8> doc_comme);
//   Type union_type;
//   SymbolTable(Value> attribute);

//  private:
//   friend EnumDef;
//   friend EnumValBuilder;
//   friend bool operator==(const EnumVal &lhs, const EnumVal &rhs);

//   EnumVal(const []const u8 &_name, i64 _val) : name(_name), value(_val) {}
//   EnumVal() : value(0) {}

//   i64 value;
// };

pub const EnumDef = struct { //  : public Definition {
    base: Definition,
    //  EnumDef() : is_union(false), uses_multiple_type_instances(false) {}

    //  Offset(reflection):Enum> Serialize(FlatBufferBuilder *builder,
    //                                     const Parser &parser) const;

    //  bool Deserialize(Parser &parser, const reflection::Enum *values);

    //  template<typename T> void ChangeEnumValue(EnumVal *ev, T new_val);
    //  void SortByValue();
    //  void RemoveDuplicates();

    //  []const u8 AllFlags() const;
    //  const EnumVal *MinValue() const;
    //  const EnumVal *MaxValue() const;
    //  // Returns the number of integer steps from v1 to v2.
    //  u64 Distance(const EnumVal *v1, const EnumVal *v2) const;
    //  // Returns the number of integer steps from Min to Max.
    //  u64 Distance() const { return Distance(MinValue(), MaxValue()); }

    //  EnumVal *ReverseLookup(i64 enum_idx,
    //                         bool skip_union_default = false) const;
    //  EnumVal *FindByValue(const []const u8 &constant) const;

    //  []const u8 ToString(const EnumVal &ev) const {
    //    return IsUInt64() ? NumToString(ev.GetAsUInt64())
    //                      : NumToString(ev.GetAsInt64());
    //  }

    //  usize size() const { return vals.vec.size(); }

    //  const std.ArrayListUnmanaged(EnumVal *> &Vals() const { return vals.vec)}

    is_union: bool = false,
    //  // Type is a union which uses type aliases where at least one type is
    //  // available under two different names.
    uses_multiple_type_instances: bool = false,
    underlying_type: Type,

    // private:

    //  friend EnumValBuilder;
    //  SymbolTable(EnumVal> val);
    vals: SymbolTable(EnumVal) = .{},

    pub fn lookup(e: EnumDef, enum_name: []const u8) ?*EnumVal {
        return e.vals.lookup(enum_name);
    }
    pub fn isUInt64(e: EnumDef) bool {
        return e.underlying_type.base_type == .ULONG;
    }

    //     uint64_t EnumDef::Distance(const EnumVal *v1, const EnumVal *v2) const {
    //   return IsUInt64() ? EnumDistanceImpl(v1.GetAsUInt64(), v2.GetAsUInt64())
    //                     : EnumDistanceImpl(v1.GetAsInt64(), v2.GetAsInt64());
    // }

    // std::string EnumDef::AllFlags() const {
    //   FLATBUFFERS_ASSERT(attributes.Lookup("bit_flags"));
    //   uint64_t u64 = 0;
    //   for (auto it = Vals().begin(); it != Vals().end(); ++it) {
    //     u64 |= (*it).GetAsUInt64();
    //   }
    //   return IsUInt64() ? NumToString(u64) : NumToString(static_cast<int64_t>(u64));
    // }

    pub fn reverseLookup(e: EnumDef, enum_idx: i64, skip_union_default: bool) ?*EnumVal {
        const skip_first = @boolToInt(e.is_union and skip_union_default);
        // for (auto it = Vals().begin() + skip_first; it != Vals().end(); ++it) {
        const end = @ptrToInt(e.vals.vec.items.ptr + e.vals.vec.items.len);
        var it = e.vals.vec.items.ptr + skip_first;
        while (@ptrToInt(it) < end) : (it += 1) {
            if (it[0].value == enum_idx) {
                return it[0];
            }
        }
        return null;
    }

    pub fn findByValue(e: EnumDef, constant: []const u8) ?*EnumVal {
        var i: i64 = 0;
        var done = false;
        if (e.isUInt64()) {
            var u: u64 = 0; // avoid reinterpret_cast of pointers
            done = util.stringToNumber(constant, &u);
            i = @bitCast(i64, u);
        } else {
            done = util.stringToNumber(constant, &i);
        }
        assert(done);
        if (!done) return null;
        return e.reverseLookup(i, false);
    }

    pub fn sortByValue(e: *EnumDef) void {
        if (e.isUInt64()) {
            const lessThan = struct {
                fn f(_: void, e1: *EnumVal, e2: *EnumVal) bool {
                    if (e1.getAsUInt64() == e2.getAsUInt64())
                        return std.mem.lessThan(u8, e1.name, e2.name);
                    return e1.getAsUInt64() < e2.getAsUInt64();
                }
            }.f;
            std.sort.sort(*EnumVal, e.vals.vec.items, {}, lessThan);
        } else {
            const lessThan = struct {
                fn f(_: void, e1: *EnumVal, e2: *EnumVal) bool {
                    if (e1.getAsInt64() == e2.getAsInt64())
                        return std.mem.lessThan(u8, e1.name, e2.name);
                    return e1.getAsInt64() < e2.getAsInt64();
                }
            }.f;
            std.sort.sort(*EnumVal, e.vals.vec.items, {}, lessThan);
        }
    }

    // void EnumDef::RemoveDuplicates() {
    //   // This method depends form SymbolTable implementation!
    //   // 1) vals.vec - owner (raw pointer)
    //   // 2) vals.dict - access map
    //   auto first = vals.vec.begin();
    //   auto last = vals.vec.end();
    //   if (first == last) return;
    //   auto result = first;
    //   while (++first != last) {
    //     if ((*result).value != (*first).value) {
    //       *(++result) = *first;
    //     } else {
    //       auto ev = *first;
    //       for (auto it = vals.dict.begin(); it != vals.dict.end(); ++it) {
    //         if (it.second == ev) it.second = *result;  // reassign
    //       }
    //       delete ev;  // delete enum value
    //       *first = null;
    //     }
    //   }
    //   vals.vec.erase(++result, last);
    // }

    pub fn changeEnumValue(_: EnumDef, ev: *EnumVal, new_value: anytype) void {
        ev.value = @intCast(i64, new_value);
    }

    pub fn size(e: EnumDef) usize {
        return e.vals.vec.items.len;
    }
};
