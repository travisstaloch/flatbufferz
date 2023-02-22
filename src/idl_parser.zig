const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const builtin = @import("builtin");
const idl = @import("idl.zig");
const Namespace = idl.Namespace;
const IncludedFile = idl.IncludedFile;
const Value = idl.Value;
const FieldDef = idl.FieldDef;
const StructDef = idl.StructDef;
const EnumDef = idl.EnumDef;
const ServiceDef = idl.ServiceDef;
const RPCCall = idl.RPCCall;
const SymbolTable = idl.SymbolTable;
const Type = idl.Type;
const BaseType = idl.BaseType;
const EnumVal = idl.EnumVal;
const Definition = idl.Definition;
const common = @import("common.zig");
const todo = common.todo;
const util = @import("util.zig");
const fbuilder = @import("flatbuffer_builder.zig");
const base = @import("base.zig");
const refl = @import("reflection.zig");
const hash = @import("hash.zig");

pub const VERSION_MAJOR = 23;
pub const VERSION_MINOR = 1;
pub const VERSION_REVISION = 21;
const kPi = 3.14159265358979323846;

pub const VERSION = std.fmt.comptimePrint(
    "{}.{}.{}",
    .{ VERSION_MAJOR, VERSION_MINOR, VERSION_REVISION },
);

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or (c == '_');
}

fn validateUTF8(str: []const u8) bool {
    // const char *s = &str[0];
    // const char *const sEnd = s + str.length();
    // while (s < sEnd) {
    //   if (FromUTF8(&s) < 0) { return false; }
    // }
    // return true;
    _ = str;
    unreachable;
}

fn isLowerSnakeCase(str: []const u8) bool {
    for (str) |c| {
        if (!util.check_ascii_range(c, 'a', 'z') and !std.ascii.isDigit(c) and c != '_')
            return false;
    }
    return true;
}

fn strFromRange(start: [*]const u8, end: [*]const u8) []const u8 {
    const len = @ptrToInt(end) - @ptrToInt(start);
    return start[0..len];
}

fn lookupTableByName(
    comptime T: type,
    alloc: mem.Allocator,
    table: SymbolTable(T),
    name: []const u8,
    current_namespace: Namespace,
    skip_top: usize,
) !?*T {
    // std.log.debug("lookupTableByName({s}, {s}) components {s}", .{ @typeName(T), name, current_namespace.components.items });
    const components = current_namespace.components;
    if (table.dict.count() == 0) return null;
    if (components.items.len < skip_top) return null;
    const N = components.items.len - skip_top;
    var full_name = std.ArrayList(u8).init(alloc);
    {
        var i: usize = 0;
        while (i < N) : (i += 1) {
            try full_name.appendSlice(components.items[i]);
            try full_name.append('.');
        }
    }
    {
        var i = N;
        while (i > 0) : (i -= 1) {
            try full_name.appendSlice(name);
            const mobj = table.lookup(full_name.items);
            if (mobj) |obj| return obj;
            const len = full_name.items.len - components.items[i - 1].len - 1 - name.len;
            full_name.shrinkAndFree(len);
        }
    }
    assert(full_name.items.len == 0);
    return table.lookup(name); // lookup in global namespace
}

fn singleValueRepack(alloc: mem.Allocator, e: *Value, val: anytype) !void {
    // Remove leading zeros.
    const vinfo = @typeInfo(@TypeOf(val));
    switch (vinfo) {
        .Int => if (e.type.base_type.isInteger()) {
            e.constant = try util.numToString(alloc, val);
        },
        .Float => if (std.math.isNan(val)) {
            e.constant = "nan";
        },
        else => unreachable,
    }
}

pub const Parser = struct {
    state: idl.ParserState = .{},
    alloc: mem.Allocator,
    path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined,
    buf_one: [1]u8 = undefined,
    types_: SymbolTable(Type) = .{},
    structs_: SymbolTable(StructDef) = .{},
    enums_: SymbolTable(EnumDef) = .{},
    services_: SymbolTable(ServiceDef) = .{},
    namespaces_: std.ArrayListUnmanaged(*Namespace) = .{},
    current_namespace_: ?*Namespace = null,
    empty_namespace_: ?*Namespace = null,
    error_: std.ArrayListUnmanaged(u8) = .{}, // User readable error_ if Parse() == false
    builder_: fbuilder.Builder = .{}, // any data contained in the file
    // flex_builder_:  flexbuffers::Builder,
    // flex_root_:  flexbuffers::Reference,
    root_struct_def_: ?*StructDef = null,
    file_identifier_: []const u8 = "",
    file_extension_: []const u8 = "",

    included_files_: std.AutoHashMapUnmanaged(u64, []const u8) = .{},
    files_included_per_file_: std.StringHashMapUnmanaged(std.HashMapUnmanaged(
        IncludedFile,
        void,
        IncludedFile.Ctx,
        std.hash_map.default_max_load_percentage,
    )) = .{},
    native_included_files_: std.ArrayListUnmanaged([]const u8) = .{},
    known_attributes_: std.StringHashMapUnmanaged(bool) = .{},
    opts: idl.Options,
    uses_flexbuffers_: bool = false,
    has_warning_: bool = false,
    advanced_features_: u64 = 0,
    file_being_parsed_: []const u8 = "",
    source_: []const u8 = "",
    field_stack_: std.ArrayListUnmanaged(struct { Value, FieldDef }) = .{},
    // TODO(cneo): Refactor parser to use string_cache more often to save
    // on memory usage.
    string_cache_: std.StringHashMapUnmanaged(void) = .{},
    // anonymous_counter_:  int,
    // parse_depth_counter_:  int,  // stack-overflow guard

    pub fn init(alloc: mem.Allocator, opts: idl.Options) Parser {
        return .{ .alloc = alloc, .opts = opts };
    }

    pub fn create(alloc: mem.Allocator, opts: idl.Options) !Parser {
        var result = Parser.init(alloc, opts);
        const ns = try alloc.create(Namespace);
        result.empty_namespace_ = ns;
        ns.* = .{};
        try result.namespaces_.append(alloc, ns);
        result.current_namespace_ = ns;
        try result.known_attributes_.ensureTotalCapacity(alloc, 25);
        result.known_attributes_.putAssumeCapacity("deprecated", true);
        result.known_attributes_.putAssumeCapacity("required", true);
        result.known_attributes_.putAssumeCapacity("key", true);
        result.known_attributes_.putAssumeCapacity("shared", true);
        result.known_attributes_.putAssumeCapacity("hash", true);
        result.known_attributes_.putAssumeCapacity("id", true);
        result.known_attributes_.putAssumeCapacity("force_align", true);
        result.known_attributes_.putAssumeCapacity("bit_flags", true);
        result.known_attributes_.putAssumeCapacity("original_order", true);
        result.known_attributes_.putAssumeCapacity("nested_flatbuffer", true);
        result.known_attributes_.putAssumeCapacity("csharp_partial", true);
        result.known_attributes_.putAssumeCapacity("streaming", true);
        result.known_attributes_.putAssumeCapacity("idempotent", true);
        result.known_attributes_.putAssumeCapacity("cpp_type", true);
        result.known_attributes_.putAssumeCapacity("cpp_ptr_type", true);
        result.known_attributes_.putAssumeCapacity("cpp_ptr_type_get", true);
        result.known_attributes_.putAssumeCapacity("cpp_str_type", true);
        result.known_attributes_.putAssumeCapacity("cpp_str_flex_ctor", true);
        result.known_attributes_.putAssumeCapacity("native_inline", true);
        result.known_attributes_.putAssumeCapacity("native_custom_alloc", true);
        result.known_attributes_.putAssumeCapacity("native_type", true);
        result.known_attributes_.putAssumeCapacity("native_type_pack_name", true);
        result.known_attributes_.putAssumeCapacity("native_default", true);
        result.known_attributes_.putAssumeCapacity("flexbuffer", true);
        result.known_attributes_.putAssumeCapacity("private", true);
        return result;
    }

    fn tokenToString(t: i32, buf: *[1]u8) []const u8 {
        switch (t) {
            256 => return "end of file",
            257 => return "string constant",
            258 => return "integer constant",
            259 => return "float constant",
            260 => return "identifie",
            else => {
                assert(t < 256);
                buf[0] = @intCast(u8, t);
                return buf;
            },
        }
    }

    fn tokenToStringId(p: Parser, t: i32, buf: *[1]u8) []const u8 {
        return if (t == Token.Identifier.int())
            p.state.attribute_.items
        else
            tokenToString(t, buf);
    }

    fn invalidToken(p: *Parser, t: i32) anyerror {
        var buf1: [1]u8 = undefined;
        var buf2: [1]u8 = undefined;
        return p.err(
            "expecting: {s} instead got: {s}",
            .{ tokenToString(t, &buf1), p.tokenToStringId(p.state.token_, &buf2) },
        );
    }

    fn isIdent(p: Parser, id: []const u8) bool {
        return p.state.token_ == @enumToInt(Token.Identifier) and mem.eql(u8, p.state.attribute_.items, id);
    }

    fn expect(p: *Parser, t: i32) !void {
        if (p.state.token_ != t) return p.invalidToken(t);
        return p.next();
    }

    fn lookupEnum(p: *Parser, id: []const u8) !?*EnumDef {
        // Search thru parent namespaces.
        return lookupTableByName(
            EnumDef,
            p.alloc,
            p.enums_,
            id,
            p.current_namespace_.?.*,
            0,
        );
    }
    fn lookupStruct(p: Parser, id: []const u8) ?*StructDef {
        const msd = p.structs_.lookup(id);
        if (msd) |sd| sd.base.refcount += 1;
        return msd;
    }

    fn lookupStructThruParentNamespaces(p: *Parser, id: []const u8) !?*StructDef {
        const msd = try lookupTableByName(
            StructDef,
            p.alloc,
            p.structs_,
            id,
            p.current_namespace_.?.*,
            1,
        );
        if (msd) |sd| sd.base.refcount += 1;
        return msd;
    }

    fn markGenerated(p: *Parser) void {
        // This function marks all existing definitions as having already
        // been generated, which signals no code for included files should be
        // generated.
        for (p.enums_.vec.items) |it|
            it.base.generated = true;
        for (p.structs_.vec.items) |it| {
            if (it.predecl) it.base.generated = true;
        }
        for (p.services_.vec.items) |it|
            it.base.generated = true;
    }

    fn uniqueNamespace(p: *Parser, ns: *Namespace) !*Namespace {
        for (p.namespaces_.items) |it| {
            if (ns.components.items.ptr == it.components.items.ptr) {
                p.alloc.destroy(ns);
                return it;
            }
        }
        try p.namespaces_.append(p.alloc, ns);
        return ns;
    }

    // bool Parser::SupportsOptionalScalars(const flatbuffers::IDLOptions &opts) {
    //   static FLATBUFFERS_CONSTEXPR unsigned long supported_langs =
    //       IDLOptions::kRust | IDLOptions::kSwift | IDLOptions::kLobster |
    //       IDLOptions::kKotlin | IDLOptions::kCpp | IDLOptions::kJava |
    //       IDLOptions::kCSharp | IDLOptions::kTs | IDLOptions::kBinary |
    //       IDLOptions::kGo | IDLOptions::kPython | IDLOptions::kJson |
    //       IDLOptions::kNim;
    //   unsigned long langs = opts.lang_to_generate;
    //   return (langs > 0 && langs < IDLOptions::kMAX) && !(langs & ~supported_langs);
    // }

    fn supportsOptionalScalars(p: Parser) bool {
        _ = p;
        // Check in general if a language isn't specified.
        // return p.opts.lang_to_generate == 0 or true; // SupportsOptionalScalars(opts);
        return true;
    }

    fn supportsDefaultVectorsAndStrings(p: Parser) bool {
        _ = p;
        // static FLATBUFFERS_CONSTEXPR unsigned long supported_langs =
        //     IDLOptions::kRust | IDLOptions::kSwift | IDLOptions::kNim;
        // return !(p.opts.lang_to_generate & ~p.supported_langs);
        return true;
    }

    fn supportsAdvancedUnionFeatures(p: Parser) bool {
        _ = p;
        // return (opts.lang_to_generate &
        //         ~(IDLOptions::kCpp | IDLOptions::kTs | IDLOptions::kPhp |
        //           IDLOptions::kJava | IDLOptions::kCSharp | IDLOptions::kKotlin |
        //           IDLOptions::kBinary | IDLOptions::kSwift | IDLOptions::kNim)) == 0;
        return true;
    }

    fn supportsAdvancedArrayFeatures(p: Parser) bool {
        _ = p;
        // return (opts.lang_to_generate &
        //         ~(IDLOptions::kCpp | IDLOptions::kPython | IDLOptions::kJava |
        //           IDLOptions::kCSharp | IDLOptions::kJsonSchema | IDLOptions::kJson |
        //           IDLOptions::kBinary | IDLOptions::kRust | IDLOptions::kTs)) == 0;
        return true;
    }

    fn parseNamespacing(p: *Parser, id: *std.ArrayList(u8), last: *[]const u8) !void {
        while (p.is('.')) {
            try p.next();
            try id.append('.');
            try id.appendSlice(p.state.attribute_.items);
            if (last.len != 0) last.* = try p.state.attribute_.toOwnedSlice(p.alloc);
            try p.expect(Token.Identifier.int());
        }
    }

    fn setRootType(p: *Parser, name: []const u8) !bool {
        p.root_struct_def_ = p.lookupStruct(name);
        if (p.root_struct_def_ == null) {
            const n = try p.current_namespace_.?.getFullyQualifiedName(p.alloc, name, .{});
            p.root_struct_def_ = p.lookupStruct(n);
        }
        return p.root_struct_def_ != null;
    }

    fn parseNamespace(p: *Parser) !void {
        // std.log.debug("parseNamespace()", .{});
        try p.next();
        var ns = try p.alloc.create(Namespace);
        ns.* = .{};
        try p.namespaces_.append(p.alloc, ns); // Store it here to not leak upon error.
        if (p.state.token_ != ';') {
            while (true) {
                try ns.components.append(p.alloc, try p.state.attribute_.toOwnedSlice(p.alloc));
                try p.expect(Token.Identifier.int());
                if (p.is('.')) try p.next() else break;
            }
        }
        _ = p.namespaces_.pop();
        p.current_namespace_ = try p.uniqueNamespace(ns);
        try p.expect(';');
    }
    fn lookupCreateStruct(
        p: *Parser,
        name: []const u8,
        opts: anytype,
    ) !?*StructDef {
        // std.log.debug("lookupCreateStruct({s}, {})", .{ name, opts });
        const create_if_new = if (opts.len > 0) opts[0] else true;
        const definition = if (opts.len > 1) opts[1] else false;
        const qualified_name = try p.current_namespace_.?.getFullyQualifiedName(p.alloc, name, .{});
        // See if it exists pre-declared by an unqualified use.
        var struct_def = p.lookupStruct(name);
        if (struct_def != null and struct_def.?.predecl) {
            if (definition) {
                // Make sure it has the current namespace, and is registered under its
                // qualified name.
                struct_def.?.base.defined_namespace = p.current_namespace_;
                try p.structs_.move(p.alloc, name, qualified_name);
            }
            return struct_def.?;
        }
        // See if it exists pre-declared by an qualified use.
        struct_def = p.lookupStruct(qualified_name);
        if (struct_def != null and struct_def.?.predecl) {
            if (definition) {
                // Make sure it has the current namespace.
                struct_def.?.base.defined_namespace = p.current_namespace_;
            }
            return struct_def.?;
        }
        if (!definition and struct_def == null) {
            struct_def = try p.lookupStructThruParentNamespaces(name);
        }
        if (struct_def == null and create_if_new) {
            struct_def = try p.alloc.create(StructDef);
            if (definition) {
                _ = try p.structs_.add(p.alloc, qualified_name, struct_def.?);
                struct_def.?.* = .{
                    .base = .{
                        .name = name,
                        .defined_namespace = p.current_namespace_,
                        .file = "",
                    },
                };
            } else {
                // Not a definition.
                // Rather than failing, we create a "pre declared" StructDef, due to
                // circular references, and check for errors at the end of parsing.
                // It is defined in the current namespace, as the best guess what the
                // final namespace will be.
                _ = try p.structs_.add(p.alloc, name, struct_def.?);
                struct_def.?.* = .{
                    .base = .{
                        .name = name,
                        .defined_namespace = p.current_namespace_,
                        .file = "",
                    },
                };
                // struct_def.original_location.reset(
                //     new std::string(file_being_parsed_ + ":" + NumToString(line_)));
            }
        }
        return struct_def;
    }

    fn startStruct(p: *Parser, name: []const u8, dest: **StructDef) !void {
        var struct_def = (try p.lookupCreateStruct(name, .{ true, true })) orelse unreachable;
        // std.log.debug("struct_def {}", .{struct_def});
        if (!struct_def.predecl)
            return p.err("datatype already exists: {s}", .{try p.current_namespace_.?.getFullyQualifiedName(p.alloc, name, .{})});
        struct_def.predecl = false;
        struct_def.base.name = name;
        struct_def.base.file = p.file_being_parsed_;
        // Move this struct to the back of the vector just in case it was predeclared,
        // to preserve declaration order.
        // *std::remove(structs_.vec.begin(), structs_.vec.end(), &struct_def) = &struct_def;
        const idx = mem.indexOfScalar(*StructDef, p.structs_.vec.items, struct_def) orelse
            unreachable;
        const x = p.structs_.vec.orderedRemove(idx);
        p.structs_.vec.appendAssumeCapacity(x);
        dest.* = struct_def;
    }

    fn checkClash(
        p: *Parser,
        fields: std.ArrayListUnmanaged(*FieldDef),
        struct_def: *StructDef,
        suffix: []const u8,
        basetype: BaseType,
    ) !void {
        const len = suffix.len;
        for (fields.items) |it| {
            const fname = it.base.name;
            if (fname.len > len and
                mem.eql(u8, fname[fname.len - len ..], suffix) and
                it.value.type.base_type != .UTYPE)
            {
                const mfield =
                    struct_def.fields.lookup(fname[0 .. fname.len - len]);
                if (mfield) |field| if (field.value.type.base_type == basetype)
                    return p.err(
                        "Field {s} would clash with generated functions for field {s}",
                        .{ fname, field.base.name },
                    );
            }
        }
    }

    fn getPooledString(p: *Parser, s: []const u8) ![]const u8 {
        const gop = try p.string_cache_.getOrPut(p.alloc, s);
        return gop.key_ptr.*;
    }

    fn tryTypedValue(p: *Parser, name: []const u8, dtoken: i32, check: bool, e: *Value, req: BaseType, destmatch: *bool) !void {
        if (false) {
            var buf1: [1]u8 = undefined;
            var buf2: [1]u8 = undefined;
            std.log.debug("tryTypedValue(name={s}, dtoken='{s}') p.state.token_='{s}'", .{ name, Token.toStr(dtoken, &buf1), Token.toStr(p.state.token_, &buf2) });
        }
        assert(destmatch.* == false and dtoken == p.state.token_);
        destmatch.* = true;
        e.constant = try p.state.attribute_.toOwnedSlice(p.alloc);
        // Check token match
        if (!check) {
            if (e.type.base_type == .NONE) {
                e.type.base_type = req;
            } else {
                return p.err("type mismatch: expecting: {s}, found: {s}, name: {s}, value: {s}", .{ e.type.base_type.typeName(), req.typeName(), name, e.constant });
            }
        }
        // The exponent suffix of hexadecimal float-point number is mandatory.
        // A hex-integer constant is forbidden as an initializer of float number.
        if ((Token.FloatConstant.int() != dtoken) and e.type.base_type.isFloat()) {
            const s = e.constant;
            const mk = mem.indexOfAny(u8, s, "0123456789.");

            if (mk) |k| {
                if ((s.len > (k + 1)) and
                    (s[k] == '0' and util.isAlphaChar(s[k + 1], 'X')) and
                    (mem.indexOfAnyPos(u8, s, k + 2, "pP") != null))
                {
                    return p.err("invalid number, the exponent suffix of hexadecimal " ++
                        "floating-point literals is mandatory: \"{s}\"", .{s});
                }
            }
        }
        try p.next();
    }

    fn parseFunction(p: *Parser, name: []const u8, e: *Value) !void {
        // TODO guard recursion depth
        // ParseDepthGuard depth_guard(this);
        // ECHECK(depth_guard.Check());
        // Copy name, attribute will be changed on NEXT().
        const functionname = try p.state.attribute_.toOwnedSlice(p.alloc);
        if (!e.type.base_type.isFloat()) {
            return p.err("{s}: type of argument mismatch, expecting: {s}, found: {s}, name: {s}, value: {s}", .{ functionname, BaseType.DOUBLE.typeName(), e.type.base_type.typeName(), name, e.constant });
        }
        try p.next();
        try p.expect('(');
        try p.parseSingleValue(name, e, false);
        try p.expect(')');
        // calculate with double precision
        var x = try std.fmt.parseFloat(f64, e.constant);
        var y: f64 = 0;

        // clang-format off
        var func_match = false;
        const FLATBUFFERS_FN_DOUBLE = struct {
            inline fn f(functionname_: []const u8, name_: []const u8, op: f64, func_match_: *bool, y_: *f64) void {
                if (!func_match_.* and mem.eql(u8, functionname_, name_)) {
                    y_.* = op;
                    func_match_.* = true;
                }
            }
        }.f;

        // #define FLATBUFFERS_FN_DOUBLE(name, op) \
        //   if (!func_match and functionname == name) { y = op; func_match = true; }
        FLATBUFFERS_FN_DOUBLE(functionname, "deg", x / kPi * 180, &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "rad", x * kPi / 180, &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "sin", @sin(x), &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "cos", @cos(x), &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "tan", @tan(x), &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "asin", std.math.asin(x), &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "acos", std.math.acos(x), &func_match, &x);
        FLATBUFFERS_FN_DOUBLE(functionname, "atan", std.math.atan(x), &func_match, &x);
        // TODO(wvo): add more useful conversion functions here.
        // #undef FLATBUFFERS_FN_DOUBLE
        // clang-format on
        if (!func_match) {
            return p.err("Unknown conversion function: {s}, field name: {s}, value: {s}", .{ functionname, name, e.constant });
        }
        e.constant = try std.fmt.allocPrint(p.alloc, "{d}", .{y}); //NumToString(y);
    }

    fn parseEnumFromString(p: *Parser, ty: Type, result: *[]const u8) !void {
        const base_type =
            if (ty.enum_def != null)
            ty.enum_def.?.underlying_type.base_type
        else
            ty.base_type;
        if (!base_type.isInteger()) return p.err("not a valid value for this field", .{});
        var u64_val: u64 = 0;
        var pos: usize = 0;
        while (pos != std.math.maxInt(u64)) {
            const delim = std.mem.indexOfScalarPos(u8, p.state.attribute_.items, pos, ' ');
            const last = delim == null;
            const word_ = try p.state.attribute_.toOwnedSlice(p.alloc);
            const word = if (!last)
                word_[pos .. delim.? - pos]
            else
                word_[pos..];
            pos = if (!last) delim.? + 1 else std.math.maxInt(usize);
            // std.log.debug("word={s} {?*}", .{ word, ty.enum_def });
            var ev: ?*EnumVal = null;
            if (ty.enum_def != null) {
                ev = ty.enum_def.?.lookup(word);
            } else {
                const dot = std.mem.indexOfScalar(u8, word, '.') orelse
                    return p.err("enum values need to be qualified by an enum type", .{});
                const enum_def_str = word[0..dot];
                std.log.debug("enum_def_str={s}", .{enum_def_str});
                const enum_def = try p.lookupEnum(enum_def_str);
                if (enum_def == null) return p.err("unknown enum: {s}", .{enum_def_str});
                const enum_val_str = word[dot + 1 ..];
                std.log.debug("enum_val_str={s}", .{enum_val_str});
                ev = enum_def.?.lookup(enum_val_str);
            }
            if (ev == null) return p.err("unknown enum value: {s}", .{word});
            u64_val |= @bitCast(u64, ev.?.value);
        }
        result.* = if (base_type.isUnsigned())
            try std.fmt.allocPrint(p.alloc, "{}", .{u64_val})
        else
            try std.fmt.allocPrint(p.alloc, "{}", .{@bitCast(i64, u64_val)});
    }

    fn IF_ECHECK(name: []const u8, e: *Value, match: *bool, force: bool, dtoken: Token, check: bool, req: BaseType, p: *Parser) !void {
        if (!match.* and dtoken.int() == p.state.token_ and (check or force))
            try p.tryTypedValue(name, dtoken.int(), check, e, req, match);
    }

    fn TRY_ECHECK(name: []const u8, e: *Value, match: *bool, dtoken: Token, check: bool, req: BaseType, p: *Parser) !void {
        return IF_ECHECK(name, e, match, false, dtoken, check, req, p);
    }

    fn FORCE_ECHECK(name: []const u8, e: *Value, match: *bool, dtoken: Token, check: bool, req: BaseType, p: *Parser) !void {
        return IF_ECHECK(name, e, match, true, dtoken, check, req, p);
    }
    fn parseSingleValue(p: *Parser, name: []const u8, e: *Value, check_now: bool) !void {
        if (p.state.token_ == '+' or p.state.token_ == '-') {
            const sign = @intCast(u8, p.state.token_);
            // Get an indentifier: NAN, INF, or function name like cos/sin/deg.
            try p.next();
            if (p.state.token_ != Token.Identifier.int())
                return p.err("constant name expected", .{});
            try p.state.attribute_.insert(p.alloc, 0, sign);
        }

        const in_type = e.type.base_type;
        const is_tok_ident = p.state.token_ == Token.Identifier.int();
        const is_tok_string = p.state.token_ == Token.StringConstant.int();

        // First see if this could be a conversion function.
        if (is_tok_ident and p.state.cursor_[0] == '(')
            return p.parseFunction(name, e);

        // clang-format off
        var match = false;

        // #define IF_ECHECK_(force, dtoken, check, req)    \
        //   if (!match and ((dtoken) == p.state.token_) and ((check) or IsConstTrue(force))) \
        //     ECHECK(TryTypedValue(name, dtoken, check, e, req, &match))
        // #define TRY_ECHECK(dtoken, check, req) IF_ECHECK_(false, dtoken, check, req)
        // #define FORCE_ECHECK(dtoken, check, req) IF_ECHECK_(true, dtoken, check, req)
        // clang-format on

        if (is_tok_ident or is_tok_string) {
            const kTokenStringOrIdent = @intToEnum(Token, p.state.token_);
            // The string type is a most probable type, check it first.
            try TRY_ECHECK(name, e, &match, kTokenStringOrIdent, in_type == .STRING, .STRING, p);

            // avoid escaped and non-ascii in the string
            if (!match and is_tok_string and in_type.isScalar() and
                !p.state.attr_is_trivial_ascii_string_)
            {
                return p.err("type mismatch or invalid value, an initializer of " ++
                    "non-string field must be trivial ASCII string: type: {s}" ++
                    ", name: {s}" ++
                    ", value: {s}", .{ in_type.typeName(), name, p.state.attribute_.items });
            }

            // A boolean as true/false. Boolean as Integer check below.
            if (!match and in_type.isBool()) {
                const is_true = mem.eql(u8, p.state.attribute_.items, "true");
                if (is_true or mem.eql(u8, p.state.attribute_.items, "false")) {
                    p.state.attribute_.items.len = 0;
                    try p.state.attribute_.appendSlice(p.alloc, if (is_true) "1" else "0");
                    // accepts both Token.StringConstant.int() and Token.Identifier.int()
                    try TRY_ECHECK(name, e, &match, kTokenStringOrIdent, in_type.isBool(), .BOOL, p);
                }
            }
            // Check for optional scalars.
            if (!match and in_type.isScalar() and mem.eql(u8, p.state.attribute_.items, "null")) {
                e.constant = "null";
                try p.next();
                match = true;
            }
            // Check if this could be a string/identifier enum value.
            // Enum can have only true integer base type.
            if (!match and in_type.isInteger() and !in_type.isBool() and
                isIdentifierStart(p.state.attribute_.items[0]))
            {
                try p.parseEnumFromString(e.type, &e.constant);
                try p.next();
                match = true;
            }
            // Parse a float/integer number from the string.
            // A "scalar-in-string" value needs extra checks.
            if (!match and is_tok_string and in_type.isScalar()) {
                // Strip trailing whitespaces from attribute_.
                if (util.findLastNotScalar(p.state.attribute_.items, ' ')) |last_non_ws|
                    // p.state.attribute_.resize(last_non_ws + 1);
                    p.state.attribute_.items.len = last_non_ws + 1;

                if (true) todo("here", .{});
                if (e.type.base_type.isFloat()) {
                    // The functions strtod() and strtof() accept both 'nan' and
                    // 'nan(number)' literals. While 'nan(number)' is rejected by the parser
                    // as an unsupported function if is_tok_ident is true.

                    if (p.state.attribute_.find_last_of(')') != null) {
                        return p.err("invalid number: {s}", .{p.state.attribute_});
                    }
                }
            }
            // Float numbers or nan, inf, pi, etc.
            try TRY_ECHECK(name, e, &match, kTokenStringOrIdent, in_type.isFloat(), .FLOAT, p);
            // An integer constant in string.
            try TRY_ECHECK(name, e, &match, kTokenStringOrIdent, in_type.isInteger(), .INT, p);
            // Unknown tokens will be interpreted as string type.
            // An attribute value may be a scalar or string constant.
            try FORCE_ECHECK(name, e, &match, .StringConstant, in_type == .STRING, .STRING, p);
        } else {
            // Try a float number.
            try TRY_ECHECK(name, e, &match, .FloatConstant, in_type.isFloat(), .FLOAT, p);
            // Integer token can init any scalar (integer of float).
            try FORCE_ECHECK(name, e, &match, .IntegerConstant, in_type.isScalar(), .INT, p);
        }
        // Match empty vectors for default-empty-vectors.
        if (!match and e.type.base_type.isVector() and p.state.token_ == '[') {
            try p.next();
            if (p.state.token_ != ']') {
                return p.err("Expected `]` in vector default", .{});
            }
            try p.next();
            match = true;
            e.constant = "[]";
        }

        if (!match) return p.err(
            "Cannot assign token starting with '{s}' to value of <{s}> type.",
            .{ p.tokenToStringId(p.state.token_, &p.buf_one), in_type.typeName() },
        );

        const match_type = e.type.base_type; // may differ from in_type
        // The check_now flag must be true when parse a fbs-schema.
        // This flag forces to check default scalar values or metadata of field.
        // For JSON parser the flag should be false.
        // If it is set for JSON each value will be checked twice (see ParseTable).
        // Special case 'null' since atot can't handle that.
        if (check_now and match_type.isScalar() and !mem.eql(u8, e.constant, "null")) {
            // clang-format off
            switch (match_type) {
                .NONE => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u8, e.constant, 10)),
                .UTYPE => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u8, e.constant, 10)),
                .BOOL => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u8, e.constant, 10)),
                .CHAR => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(i8, e.constant, 10)),
                .UCHAR => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u8, e.constant, 10)),
                .SHORT => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(i16, e.constant, 10)),
                .USHORT => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u16, e.constant, 10)),
                .INT => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(i32, e.constant, 10)),
                .UINT => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u32, e.constant, 10)),
                .LONG => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(i64, e.constant, 10)),
                .ULONG => try singleValueRepack(p.alloc, e, try std.fmt.parseInt(u64, e.constant, 10)),
                .FLOAT => try singleValueRepack(p.alloc, e, try std.fmt.parseFloat(f32, e.constant)),
                .DOUBLE => try singleValueRepack(p.alloc, e, try std.fmt.parseFloat(f64, e.constant)),
                else => todo("parseSingleValue .{s}", .{match_type.typeName()}),
            }
            // clang-format on
        }
    }

    fn parseMetaData(p: *Parser, attributes: *SymbolTable(Value)) !void {
        if (p.is('(')) {
            try p.next();
            while (true) {
                var name = try p.state.attribute_.toOwnedSlice(p.alloc);
                if (!(p.is(Token.Identifier.int()) or p.is(Token.StringConstant.int())))
                    return p.err("attribute name must be either identifier or string: {s}", .{name});
                if (p.known_attributes_.get(name) == null)
                    return p.err("user define attributes must be declared before use: {s}", .{name});
                try p.next();
                const e = try p.alloc.create(Value);
                e.* = .{ .type = Type.init(.NONE, null, null, 0) };
                if (try attributes.add(p.alloc, name, e))
                    try p.warn("attribute already found: {s}", .{name});
                if (p.is(':')) {
                    try p.next();
                    try p.parseSingleValue(name, e, true);
                }
                if (p.is(')')) {
                    try p.next();
                    break;
                }
                try p.expect(',');
            }
        }
    }

    fn parseTypeIdent(p: *Parser, ty: *Type) !void {
        var id_ = std.ArrayList(u8).init(p.alloc);
        try id_.appendSlice(p.state.attribute_.items);
        try p.expect(Token.Identifier.int());
        var x: []const u8 = "";
        try p.parseNamespacing(&id_, &x);
        const id = try id_.toOwnedSlice();
        const enum_def = try p.lookupEnum(id);
        if (enum_def != null) {
            ty.* = enum_def.?.underlying_type;
            if (enum_def.?.is_union) ty.base_type = .UNION;
        } else {
            ty.base_type = .STRUCT;
            ty.struct_def = try p.lookupCreateStruct(id, .{});
        }
    }

    // Parse any IDL type.
    fn parseType(p: *Parser, ty: *Type) !void {
        if (p.state.token_ == Token.Identifier.int()) {
            if (p.isIdent("bool")) {
                ty.base_type = .BOOL;
                try p.next();
            } else if (p.isIdent("byte") or p.isIdent("int8")) {
                ty.base_type = .CHAR;
                try p.next();
            } else if (p.isIdent("ubyte") or p.isIdent("uint8")) {
                ty.base_type = .UCHAR;
                try p.next();
            } else if (p.isIdent("short") or p.isIdent("int16")) {
                ty.base_type = .SHORT;
                try p.next();
            } else if (p.isIdent("ushort") or p.isIdent("uint16")) {
                ty.base_type = .USHORT;
                try p.next();
            } else if (p.isIdent("int") or p.isIdent("int32")) {
                ty.base_type = .INT;
                try p.next();
            } else if (p.isIdent("uint") or p.isIdent("uint32")) {
                ty.base_type = .UINT;
                try p.next();
            } else if (p.isIdent("long") or p.isIdent("int64")) {
                ty.base_type = .LONG;
                try p.next();
            } else if (p.isIdent("ulong") or p.isIdent("uint64")) {
                ty.base_type = .ULONG;
                try p.next();
            } else if (p.isIdent("float") or p.isIdent("float32")) {
                ty.base_type = .FLOAT;
                try p.next();
            } else if (p.isIdent("double") or p.isIdent("float64")) {
                ty.base_type = .DOUBLE;
                try p.next();
            } else if (p.isIdent("string")) {
                ty.base_type = .STRING;
                try p.next();
            } else {
                try p.parseTypeIdent(ty);
            }
        } else if (p.state.token_ == '[') {
            // TODO check depth
            // ParseDepthGuard depth_guard(this);
            // ECHECK(depth_guard.Check());
            try p.next();
            var subtype: Type = undefined;
            try p.parseType(&subtype);
            if (subtype.isSeries())
                // We could support this, but it will complicate things, and it's
                // easier to work around with a struct around the inner vector.
                return p.err("nested vector types not supported (wrap in table first)", .{});

            if (p.state.token_ == ':') {
                try p.next();
                if (p.state.token_ != Token.IntegerConstant.int()) {
                    return p.err("length of fixed-length array must be an integer value", .{});
                }
                var fixed_length: u16 = 0;
                var check = util.stringToNumber(p.state.attribute_.items, &fixed_length);
                if (!check or fixed_length < 1) {
                    return p.err("length of fixed-length array must be positive and fit to u16 type", .{});
                }
                ty.* = Type.init(.ARRAY, subtype.struct_def, subtype.enum_def, fixed_length);
                try p.next();
            } else {
                ty.* = Type.init(.VECTOR, subtype.struct_def, subtype.enum_def, 0);
            }
            ty.element = subtype.base_type;
            try p.expect(']');
        } else {
            return p.err("illegal type syntax", .{});
        }
    }

    fn addField(p: *Parser, struct_def: *StructDef, name_: []const u8, name_suffix: []const u8, ty: Type, dest: *?*FieldDef) !void {
        var field = try p.alloc.create(FieldDef);
        const name = try std.mem.concat(p.alloc, u8, &.{ name_, name_suffix });
        field.* = .{
            .base = .{
                .name = name,
                .file = struct_def.base.file,
            },
            .value = .{
                .type = ty,
                .offset = fbuilder.fieldIndexToOffset(@intCast(u16, struct_def.fields.vec.items.len)),
            },
        };
        if (struct_def.fixed) { // statically compute the field offset
            const size = ty.inlineSize();
            const alignment = ty.inlineAlignment();
            // structs_ need to have a predictable format, so we need to align to
            // the largest scalar
            struct_def.minalign = @max(struct_def.minalign, alignment);
            struct_def.padLastField(alignment);
            field.value.offset = @intCast(u16, struct_def.bytesize);
            struct_def.bytesize += size;
        }
        if (try struct_def.fields.add(p.alloc, name, field))
            return p.err("field already exists: {s}", .{name});
        dest.* = field;
    }

    fn parseField(p: *Parser, struct_def: *StructDef) !void {
        const name = try p.state.attribute_.toOwnedSlice(p.alloc);

        if (try p.lookupCreateStruct(name, .{ false, false }) != null)
            return p.err("field name can not be the same as table/struct name", .{});

        if (!isLowerSnakeCase(name)) {
            p.warn("field names should be lowercase snake_case, got: {s}", .{name}) catch {};
        }

        var dc = p.state.doc_comment_;
        try p.expect(Token.Identifier.int());
        try p.expect(':');
        var ty = Type.init(.NONE, null, null, 0);
        try p.parseType(&ty);

        if (struct_def.fixed) {
            if (ty.isIncompleteStruct() or
                (ty.base_type.isArray() and ty.vectorType().isIncompleteStruct()))
            {
                const type_name = if (ty.base_type.isArray())
                    ty.vectorType().struct_def.?.base.name
                else
                    ty.struct_def.?.base.name;
                return p.err("Incomplete type in struct is not allowed, type name: {s}", .{type_name});
            }

            var valid = ty.base_type.isScalar() or ty.base_type.isStruct();
            if (!valid and ty.base_type.isArray()) {
                const elem_type = ty.vectorType();
                valid = valid or elem_type.base_type.isScalar() or elem_type.base_type.isStruct();
            }
            if (!valid)
                return p.err("structs may contain only scalar or struct fields", .{});
        }

        if (!struct_def.fixed and ty.base_type.isArray())
            return p.err("fixed-length array in table must be wrapped in struct", .{});

        if (ty.base_type.isArray()) {
            p.advanced_features_ |= refl.AdvancedFeatures.AdvancedArrayFeatures.int();
            if (!p.supportsAdvancedArrayFeatures()) {
                return p.err("Arrays are not yet supported in all the specified programming languages.", .{});
            }
        }

        var mtypefield: ?*FieldDef = null;
        if (ty.base_type == .UNION) {
            // For union fields, add a second auto-generated field to hold the type,
            // with a special suffix.
            try p.addField(struct_def, name, refl.union_type_field_suffix, ty.enum_def.?.underlying_type, &mtypefield);
        } else if (ty.base_type.isVector() and ty.element == .UNION) {
            p.advanced_features_ |= refl.AdvancedFeatures.AdvancedUnionFeatures.int();
            // Only cpp, js and ts supports the union vector feature so far.
            if (!p.supportsAdvancedUnionFeatures()) {
                return p.err("Vectors of unions are not yet supported in at least one of the specified programming languages.", .{});
            }
            // For vector of union fields, add a second auto-generated vector field to
            // hold the types, with a special suffix.
            var union_vector = Type.init(.VECTOR, null, ty.enum_def, 0);
            union_vector.element = .UTYPE;
            try p.addField(struct_def, name, refl.union_type_field_suffix, union_vector, &mtypefield);
        }

        var mfield: ?*FieldDef = null;
        try p.addField(struct_def, name, "", ty, &mfield);
        const field = mfield orelse unreachable;
        if (mtypefield) |typefield| {
            // We preserve the relation between the typefield
            // and field, so we can easily map it in the code
            // generators.
            typefield.sibling_union_field = field;
            field.sibling_union_field = typefield;
        }

        if (p.state.token_ == '=') {
            try p.next();
            try p.parseSingleValue(field.base.name, &field.value, true);
            if (ty.base_type.isStruct() or (struct_def.fixed and !mem.eql(u8, field.value.constant, "0")))
                return p.err("default values are not supported for struct fields, table fields, or in structs.", .{});
            if (ty.base_type.isString() or ty.base_type.isVector()) {
                p.advanced_features_ |= refl.AdvancedFeatures.DefaultVectorsAndStrings.int();
                if (!mem.eql(u8, field.value.constant, "0") and !p.supportsDefaultVectorsAndStrings()) {
                    return p.err("Default values for strings and vectors are not supported in one of the specified programming languages", .{});
                }
            }

            if (ty.base_type.isVector() and !mem.eql(u8, field.value.constant, "0") and
                !mem.eql(u8, field.value.constant, "[]"))
            {
                return p.err("The only supported default for vectors is `[]`.", .{});
            }
        }

        // Append .0 if the value has not it (skip hex and scientific floats).
        // This suffix needed for generated C++ code.
        if (ty.base_type.isFloat()) {
            const text = field.value.constant;
            assert(text.len != 0);
            var s = text.ptr;

            while (s[0] == ' ') s += 1;
            if (s[0] == '-' or s[0] == '+') s += 1;
            // 1) A float constants (nan, inf, pi, etc) is a kind of identifier.
            // 2) A float number needn't ".0" at the end if it has exponent.
            if ((!isIdentifierStart(s[0])) and
                (mem.indexOfAny(u8, field.value.constant, ".eEpP") == null))
            {
                // TODO free old field.value.constant
                // const tmp = field.value.constant.ptr;
                // defer p.alloc.free(tmp);
                field.value.constant = try std.fmt.allocPrint(
                    p.alloc,
                    "{s}.0",
                    .{field.value.constant},
                );
            }
        }

        field.base.doc_comment = dc;
        try p.parseMetaData(&field.base.attributes);
        field.deprecated = field.base.attributes.lookup("deprecated") != null;
        const mhash_name = field.base.attributes.lookup("hash");
        if (mhash_name) |hash_name| {
            switch (if (ty.base_type.isVector()) ty.element else ty.base_type) {
                .SHORT,
                .USHORT,
                => if (hash.findHashFunction(16, hash_name.constant) == null)
                    return p.err(
                        "Unknown hashing algorithm for 16 bit types: {s}",
                        .{hash_name.constant},
                    ),
                .INT,
                .UINT,
                => if (hash.findHashFunction(32, hash_name.constant) == null)
                    return p.err(
                        "Unknown hashing algorithm for 32 bit types: {s}",
                        .{hash_name.constant},
                    ),
                .LONG,
                .ULONG,
                => if (hash.findHashFunction(64, hash_name.constant) == null)
                    return p.err(
                        "Unknown hashing algorithm for 64 bit types: {s}",
                        .{hash_name.constant},
                    ),
                else => return p.err("only short, ushort, int, uint, long and" ++
                    " ulong data types support hashing.", .{}),
            }
        }

        // For historical convenience reasons, string keys are assumed required.
        // Scalars are kDefault unless otherwise specified.
        // Nonscalars are kOptional unless required;
        field.key = field.base.attributes.lookup("key") != null;
        const required = field.base.attributes.lookup("required") != null or
            (ty.base_type.isString() and field.key);
        const default_str_or_vec =
            ((ty.base_type.isString() or ty.base_type.isVector()) and
            !mem.eql(u8, field.value.constant, "0"));
        const optional = if (ty.base_type.isScalar())
            mem.eql(u8, field.value.constant, "null")
        else
            !(required or default_str_or_vec);
        if (required and optional) {
            return p.err("Fields cannot be both optional and required.", .{});
        }
        field.presence = FieldDef.makeFieldPresence(optional, required);

        if (required and (struct_def.fixed or ty.base_type.isScalar())) {
            return p.err("only non-scalar fields in tables may be 'required'", .{});
        }
        if (field.key) {
            if (struct_def.has_key) return p.err("only one field may be set as 'key'", .{});
            struct_def.has_key = true;
            var is_valid = ty.base_type.isScalar() or ty.isString() or ty.isStruct();
            if (ty.isArray()) {
                is_valid = is_valid or
                    ty.vectorType().base_type.isScalar() or ty.vectorType().isStruct();
            }
            if (!is_valid)
                return p.err("'key' field must be string, scalar type or" ++
                    " fixed size array of scalars", .{});
        }

        if (field.isScalarOptional()) {
            p.advanced_features_ |= refl.AdvancedFeatures.OptionalScalars.int();
            if (ty.enum_def != null and ty.enum_def.?.lookup("null") != null) {
                assert(ty.base_type.isInteger());
                return p.err("the default 'null' is reserved for declaring" ++
                    " optional scalar fields, it conflicts with declaration" ++
                    " of enum '{s}'.", .{ty.enum_def.?.base.name});
            }
            if (field.base.attributes.lookup("key") != null)
                return p.err("only a non-optional scalar field can be used as" ++
                    " a 'key' field", .{});
            if (!p.supportsOptionalScalars())
                return p.err("Optional scalars are not yet supported in at" ++
                    " least one of the specified programming languages.", .{});
        }

        if (ty.enum_def != null) {
            // Verify the enum's type and default value.
            const constant = field.value.constant;
            const is_zero = mem.eql(u8, constant, "0");
            if (ty.base_type == .UNION) {
                if (!is_zero) return p.err("Union defaults must be NONE", .{});
            } else if (ty.isVector()) {
                if (!is_zero and !mem.eql(u8, constant, "[]")) {
                    return p.err("Vector defaults may only be `[]`.", .{});
                }
            } else if (ty.isArray()) {
                if (!is_zero) {
                    return p.err("Array defaults are not supported yet.", .{});
                }
            } else {
                if (!ty.base_type.isInteger()) {
                    return p.err("Enums must have integer base types", .{});
                }
                // Optional and bitflags enums may have default constants that are not
                // their specified variants.
                if (!field.isOptional() and
                    ty.enum_def.?.base.attributes.lookup("bit_flags") == null)
                {
                    if (ty.enum_def.?.findByValue(constant) == null) {
                        return p.err(
                            "default value of `{s}` for field `{s}`" ++
                                " is not part of enum `{s}`.",
                            .{ constant, name, ty.enum_def.?.base.name },
                        );
                    }
                }
            }
        }

        if (field.deprecated and struct_def.fixed)
            return p.err("can't deprecate fields in a struct", .{});

        const cpp_type = field.base.attributes.lookup("cpp_type");
        if (cpp_type != null) {
            if (mhash_name == null)
                return p.err("cpp_type can only be used with a hashed field", .{});
            // forcing cpp_ptr_type to 'naked' if unset
            const cpp_ptr_type = field.base.attributes.lookup("cpp_ptr_type");
            if (cpp_ptr_type == null) {
                var val = try p.alloc.create(Value);
                val.* = .{
                    .type = cpp_type.?.type,
                    .constant = "naked",
                };
                _ = try field.base.attributes.add(p.alloc, "cpp_ptr_type", val);
            }
        }

        field.shared = field.base.attributes.lookup("shared") != null;
        if (field.shared and field.value.type.base_type != .STRING)
            return p.err("shared can only be defined on strings", .{});

        const field_native_custom_alloc =
            field.base.attributes.lookup("native_custom_alloc");
        if (field_native_custom_alloc != null)
            return p.err("native_custom_alloc can only be used with a table" ++
                " or struct definition", .{});

        field.native_inline = field.base.attributes.lookup("native_inline") != null;
        if (field.native_inline and !field.value.type.isStruct() and
            !field.value.type.isVectorOfStruct() and
            !field.value.type.isVectorOfTable())
            return p.err("'native_inline' can only be defined on structs," ++
                " vector of structs or vector of tables", .{});

        const mnested = field.base.attributes.lookup("nested_flatbuffer");
        if (mnested) |nested| {
            if (nested.type.base_type != .STRING)
                return p.err("nested_flatbuffer attribute must be a string" ++
                    " (the root type)", .{});
            if (ty.base_type != .VECTOR or ty.element != .UCHAR)
                return p.err("nested_flatbuffer attribute may only apply to a" ++
                    " vector of ubyte", .{});
            // This will cause an error if the root type of the nested flatbuffer
            // wasn't defined elsewhere.
            field.nested_flatbuffer = try p.lookupCreateStruct(nested.constant, .{});
        }

        if (field.base.attributes.lookup("flexbuffer") != null) {
            field.flexbuffer = true;
            p.uses_flexbuffers_ = true;
            if (ty.base_type != .VECTOR or ty.element != .UCHAR)
                return p.err("flexbuffer attribute may only apply to a vector" ++
                    " of ubyte", .{});
        }

        if (mtypefield) |typefield| {
            if (!typefield.value.type.base_type.isScalar()) {
                // this is a union vector field
                typefield.presence = field.presence;
            }
            // If this field is a union, and it has a manually assigned id,
            // the automatically added type field should have an id as well (of N - 1).
            const mattr = field.base.attributes.lookup("id");
            if (mattr) |attr| {
                const id_str = attr.constant;
                var done = true;
                var id: u64 = std.fmt.parseUnsigned(u16, id_str, 10) catch blk: {
                    done = false;
                    break :blk 0;
                };
                if (done and id > 0) {
                    var val = try p.alloc.create(Value);
                    val.* = .{
                        .type = attr.type,
                        .constant = try util.numToString(p.alloc, id - 1),
                    };
                    _ = try typefield.base.attributes.add(p.alloc, "id", val);
                } else {
                    return p.err(
                        "a union type effectively adds two fields with" ++
                            " non-negative ids, its id must be that of the second " ++
                            "field (the first field is the type field and not" ++
                            " explicitly declared in the schema);\nfield: {s}, id: {s}",
                        .{ field.base.name, id_str },
                    );
                }
            }
            // if this field is a union that is deprecated,
            // the automatically added type field should be deprecated as well
            if (field.deprecated) {
                typefield.deprecated = true;
            }
        }

        try p.expect(';');
    }

    fn parseAlignAttribute(
        p: *Parser,
        align_constant: []const u8,
        min_align: usize,
        align_: *usize,
    ) !void {
        // Use u8 to avoid problems with size_t==`unsigned long` on LP64.
        var align_value: u8 = undefined;
        if (util.stringToNumber(align_constant, &align_value) and
            base.verifyAlignmentRequirements(align_value, .{ .min_align = min_align }))
        {
            align_.* = align_value;
            return;
        }
        return p.err(
            "unexpected force_align value '{s}" ++
                "', alignment must be a power of two integer ranging from the " ++
                "type\'s natural alignment {} to {}",
            .{ align_constant, min_align, base.FLATBUFFERS_MAX_ALIGNMENT },
        );
    }

    fn parseDecl(p: *Parser, filename: []const u8) !void {
        // std.log.debug("parseDecl() {s}:{} token '{s}':{} cursor_={s}", .{ filename, p.state.line_, Token.toStr(p.state.token_, &p.buf_one), p.state.token_, p.state.cursor_[0..5] });
        std.log.debug(
            "parseDecl() token '{s}':{} cursor_={s}",
            .{
                Token.toStr(p.state.token_, &p.buf_one),
                p.state.token_,
                p.state.cursor_[0..5],
            },
        );
        var dc = p.state.doc_comment_;
        const fixed = p.isIdent("struct");
        if (!fixed and !p.isIdent("table"))
            return p.err("declaration expected", .{});
        try p.next();
        const name = try p.state.attribute_.toOwnedSlice(p.alloc);
        try p.expect(Token.Identifier.int());
        var struct_def = try p.alloc.create(StructDef);
        try p.startStruct(name, &struct_def);
        struct_def.base.doc_comment = dc;
        struct_def.fixed = fixed;
        if (filename.len > 0 and p.opts.project_root.len > 0) {
            struct_def.base.declaration_file =
                try p.getPooledString(try util.relativeToRootPath(
                p.alloc,
                p.opts.project_root,
                filename,
            ));
        }
        try p.parseMetaData(&struct_def.base.attributes);
        struct_def.sortbysize =
            struct_def.base.attributes.lookup("original_order") == null and !fixed;
        try p.expect('{');
        while (p.state.token_ != '}') try p.parseField(struct_def);
        if (fixed) {
            const mforce_align = struct_def.base.attributes.lookup("force_align");
            if (mforce_align) |force_align| {
                var align_: usize = undefined;
                try p.parseAlignAttribute(force_align.constant, struct_def.minalign, &align_);
                struct_def.minalign = align_;
            }
            if (struct_def.bytesize == 0) return p.err("size 0 structs not allowed", .{});
        }
        struct_def.padLastField(struct_def.minalign);
        // Check if this is a table that has manual id assignments
        var fields = struct_def.fields.vec;
        if (!fixed and fields.items.len > 0) {
            var num_id_fields: usize = 0;
            for (fields.items) |it| {
                if (it.base.attributes.lookup("id") != null) num_id_fields += 1;
            }

            // If any fields have ids..
            if (num_id_fields > 0 or p.opts.require_explicit_ids) {
                // Then all fields must have them.
                if (num_id_fields != fields.items.len) {
                    if (p.opts.require_explicit_ids) {
                        return p.err("all fields must have an 'id' attribute when " ++
                            "--require-explicit-ids is used", .{});
                    } else {
                        return p.err("either all fields or no fields must have" ++
                            " an 'id' attribute", .{});
                    }
                }
                // Simply sort by id, then the fields are the same as if no ids had
                // been specified.
                const compareFieldDefs = struct {
                    fn sort(_: void, a: *FieldDef, b: *FieldDef) bool {
                        const aid = std.fmt.parseInt(u16, a.base.attributes.lookup("id").?.constant, 10) catch
                            unreachable;
                        const bid = std.fmt.parseInt(u16, b.base.attributes.lookup("id").?.constant, 10) catch
                            unreachable;
                        return aid < bid;
                    }
                }.sort;
                std.sort.sort(*FieldDef, fields.items, {}, compareFieldDefs); //, );
                // Verify we have a contiguous set, and reassign vtable offsets.
                assert(fields.items.len <= std.math.maxInt(u16));
                var i: u16 = 0;
                while (i < fields.items.len) : (i += 1) {
                    const field = fields.items[i];
                    const id_str = field.base.attributes.lookup("id").?.constant;

                    // Metadata values have a dynamic type, they can be `float`, 'int', or
                    // 'string`.
                    // The FieldIndexToOffset(i) expects the voffset_t so `id` is limited by
                    // this type.
                    const id = std.fmt.parseUnsigned(u16, id_str, 10) catch
                        return p.err("field id\'s must be non-negative number" ++
                        ", field: {s} , id: {s}", .{ field.base.name, id_str });
                    if (i != id) return p.err(
                        "field id\'s must be consecutive" ++
                            " from 0, id {} missing or set twice, field: {s}, id: {s}",
                        .{ i, field.base.name, id_str },
                    );
                    field.value.offset = fbuilder.fieldIndexToOffset(i);
                }
            }
        }

        try p.checkClash(fields, struct_def, refl.union_type_field_suffix, .UNION);
        try p.checkClash(fields, struct_def, "Type", .UNION);
        try p.checkClash(fields, struct_def, "_length", .VECTOR);
        try p.checkClash(fields, struct_def, "Length", .VECTOR);
        try p.checkClash(fields, struct_def, "_byte_vector", .STRING);
        try p.checkClash(fields, struct_def, "ByteVector", .STRING);
        try p.expect('}');
        const qualified_name =
            try p.current_namespace_.?.getFullyQualifiedName(p.alloc, struct_def.base.name, .{});
        const ty = try p.alloc.create(Type);
        ty.* = Type.init(.STRUCT, struct_def, null, 0);
        if (try p.types_.add(p.alloc, qualified_name, ty))
            return p.err("datatype already exists: {s}", .{qualified_name});
    }
    fn parseService(p: *Parser, filename: []const u8) !void {
        const service_comment = p.state.doc_comment_;
        try p.next();
        const service_name = try p.state.attribute_.toOwnedSlice(p.alloc);
        try p.expect(Token.Identifier.int());
        var service_def = try p.alloc.create(ServiceDef);
        service_def.* = .{
            .base = .{
                .name = service_name,
                .file = p.file_being_parsed_,
                .doc_comment = service_comment,
                .defined_namespace = p.current_namespace_,
            },
        };
        if (filename.len != 0 and p.opts.project_root.len != 0) {
            service_def.base.declaration_file =
                try p.getPooledString(try util.relativeToRootPath(p.alloc, p.opts.project_root, filename));
        }
        const qname = try p.current_namespace_.?.getFullyQualifiedName(p.alloc, service_name, .{});
        if (try p.services_.add(p.alloc, qname, service_def))
            return p.err("service already exists: {s}", .{service_name});
        try p.parseMetaData(&service_def.base.attributes);
        try p.expect('{');
        while (true) {
            const doc_comment = p.state.doc_comment_;
            const rpc_name = try p.state.attribute_.toOwnedSlice(p.alloc);
            try p.expect(Token.Identifier.int());
            try p.expect('(');
            var reqtype: Type = undefined;
            try p.parseTypeIdent(&reqtype);
            try p.expect(')');
            try p.expect(':');
            var resptype: Type = undefined;
            try p.parseTypeIdent(&resptype);
            if (reqtype.base_type != .STRUCT or reqtype.struct_def.?.fixed or
                resptype.base_type != .STRUCT or resptype.struct_def.?.fixed)
                return p.err("rpc request and response types must be tables", .{});
            // auto &rpc = *new RPCCall();
            var rpc = try p.alloc.create(RPCCall);
            rpc.* = .{
                .base = .{
                    .name = rpc_name,
                    .doc_comment = doc_comment,
                    .file = "",
                },
                .request = reqtype.struct_def,
                .response = resptype.struct_def,
            };
            if (try service_def.calls.add(p.alloc, rpc_name, rpc))
                return p.err("rpc already exists: {s}", .{rpc_name});
            try p.parseMetaData(&rpc.base.attributes);
            try p.expect(';');
            if (p.state.token_ == '}') break;
        }
        try p.next();
    }

    fn startEnum(p: *Parser, name: []const u8, is_union: bool, dest: ?**EnumDef) !void {
        var enum_def = try p.alloc.create(EnumDef);
        enum_def.* = .{
            .base = .{
                .name = name,
                .file = p.file_being_parsed_,
                .doc_comment = p.state.doc_comment_,
                .defined_namespace = p.current_namespace_,
            },
            .is_union = is_union,
            .underlying_type = .{
                .base_type = if (is_union) .UTYPE else .INT,
                .enum_def = enum_def,
                .struct_def = null,
            },
        };
        const qualified_name =
            try p.current_namespace_.?.getFullyQualifiedName(p.alloc, name, .{});
        if (try p.enums_.add(p.alloc, qualified_name, enum_def))
            return p.err("enum already exists: {s}", .{qualified_name});
        if (dest) |d| d.* = enum_def;
    }
    pub const EnumValBuilder = struct {
        parser: *Parser,
        enum_def: *EnumDef,
        temp: ?*EnumVal = null,
        user_value: bool = false,

        pub fn init(
            parser: *Parser,
            enum_def: *EnumDef,
        ) EnumValBuilder {
            return .{
                .parser = parser,
                .enum_def = enum_def,
            };
        }

        fn createEnumerator(
            e: *EnumValBuilder,
            alloc: mem.Allocator,
            ev_name: []const u8,
        ) !*EnumVal {
            assert(e.temp == null);
            const first = e.enum_def.vals.vec.items.len == 0;
            e.user_value = first;
            const new = try alloc.create(EnumVal);
            e.temp = new;
            new.* = EnumVal{
                .name = ev_name,
                .value = if (first) 0 else e.enum_def.vals.vec.getLast().value,
                .union_type = .{},
            };
            return new;
        }

        fn createEnumeratorV(
            e: *EnumValBuilder,
            alloc: mem.Allocator,
            ev_name: []const u8,
            val: i64,
        ) !*EnumVal {
            assert(e.temp == null);
            e.user_value = true;
            e.temp = try alloc.create(EnumVal);
            e.temp.* = EnumVal{ .name = ev_name, .value = val };
            return e.temp;
        }

        fn acceptEnumerator_(e: *EnumValBuilder) !void {
            return e.acceptEnumerator(e.temp.?.name);
        }
        fn acceptEnumerator(e: *EnumValBuilder, name: []const u8) !void {
            assert(e.temp != null);
            try e.validateValue(&e.temp.?.value, !e.user_value);
            // std.log.debug("e.temp.?.union_type.enum_def {*} e.enum_def {*}", .{ e.temp.?.union_type.enum_def, e.enum_def });
            assert((e.temp.?.union_type.enum_def == null) or
                (e.temp.?.union_type.enum_def.? == e.enum_def));
            const not_unique = try e.enum_def.vals.add(e.parser.alloc, name, e.temp.?);
            e.temp = null;
            if (not_unique) return e.parser.err("enum value already exists: {s}", .{name});
        }

        fn assignEnumeratorValue(e: *EnumValBuilder, value: []const u8) !void {
            e.user_value = true;
            var fit = false;
            if (e.enum_def.isUInt64()) {
                var u: u64 = undefined;
                fit = util.stringToNumber(value, &u);
                e.temp.?.value = @intCast(i64, u);
            } else {
                var i: i64 = undefined;
                fit = util.stringToNumber(value, &i);
                e.temp.?.value = i;
            }
            if (!fit) return e.parser.err("enum value does not fit, \"{s}\"", .{value});
        }

        fn validateImpl(e: *EnumValBuilder, comptime _: BaseType, comptime T: type, ev: *i64, m: T) !void {
            const tinfo = @typeInfo(T);
            const v = if (tinfo == .Int) @intCast(T, ev.*) else @intToFloat(T, ev.*);
            const up: T = if (tinfo == .Int) std.math.maxInt(T) else std.math.floatMax(T);
            const dn: T = if (tinfo == .Int) std.math.minInt(T) else std.math.floatMin(T);
            if (v < dn or v > (up - m)) {
                return e.parser.err(
                    "enum value does not fit, \"{} out of {s}\" {s}",
                    .{ v, if (m != 0) " + 1" else "", @typeName(T) },
                );
            }
            ev.* = if (tinfo == .Int) @intCast(i64, v + m) else unreachable;
        }

        fn validateValue(e: *EnumValBuilder, ev: *i64, n: bool) !void {
            switch (e.enum_def.underlying_type.base_type) {
                .NONE => if (BaseType.NONE.isInteger())
                    return e.validateImpl(.NONE, u8, ev, @as(u8, if (n) 1 else 0)),
                .UTYPE => if (BaseType.UTYPE.isInteger())
                    return e.validateImpl(.UTYPE, u8, ev, @as(u8, if (n) 1 else 0)),
                .BOOL => if (BaseType.BOOL.isInteger())
                    return e.validateImpl(.BOOL, u8, ev, @as(u8, if (n) 1 else 0)),
                .CHAR => if (BaseType.CHAR.isInteger())
                    return e.validateImpl(.CHAR, i8, ev, @as(i8, if (n) 1 else 0)),
                .UCHAR => if (BaseType.UCHAR.isInteger())
                    return e.validateImpl(.UCHAR, u8, ev, @as(u8, if (n) 1 else 0)),
                .SHORT => if (BaseType.SHORT.isInteger())
                    return e.validateImpl(.SHORT, i16, ev, @as(i16, if (n) 1 else 0)),
                .USHORT => if (BaseType.USHORT.isInteger())
                    return e.validateImpl(.USHORT, u16, ev, @as(u16, if (n) 1 else 0)),
                .INT => if (BaseType.INT.isInteger())
                    return e.validateImpl(.INT, i32, ev, @as(i32, if (n) 1 else 0)),
                .UINT => if (BaseType.UINT.isInteger())
                    return e.validateImpl(.UINT, u32, ev, @as(u32, if (n) 1 else 0)),
                .LONG => if (BaseType.LONG.isInteger())
                    return e.validateImpl(.LONG, i64, ev, @as(i64, if (n) 1 else 0)),
                .ULONG => if (BaseType.ULONG.isInteger())
                    return e.validateImpl(.ULONG, u64, ev, @as(u64, if (n) 1 else 0)),
                .FLOAT => if (BaseType.FLOAT.isInteger())
                    return e.validateImpl(.FLOAT, f32, ev, @as(f32, if (n) 1 else 0)),
                .DOUBLE => if (BaseType.DOUBLE.isInteger())
                    return e.validateImpl(.DOUBLE, f64, ev, @as(f64, if (n) 1 else 0)),
                else => unreachable,
            }
        }

        // EnumValBuilder(Parser &_parser, EnumDef &_enum_def)
        //     : parser(_parser),
        //       enum_def(_enum_def),
        //       temp(null),
        //       user_value(false) {}

        // ~EnumValBuilder() { delete temp; }

    };

    fn parseEnum(p: *Parser, is_union: bool, dest: ?**EnumDef, filename: []const u8) !void {
        var enum_comment = p.state.doc_comment_;
        try p.next();
        const enum_name = try p.state.attribute_.toOwnedSlice(p.alloc);
        try p.expect(Token.Identifier.int());
        var enum_def: *EnumDef = undefined;
        std.log.debug("parseEnum() enum_name={s}", .{enum_name});
        try p.startEnum(enum_name, is_union, &enum_def);
        if (filename.len != 0 and p.opts.project_root.len != 0) {
            enum_def.base.declaration_file =
                try p.getPooledString(
                try util.relativeToRootPath(p.alloc, p.opts.project_root, filename),
            );
        }
        enum_def.base.doc_comment = enum_comment;
        if (!is_union and !p.opts.proto_mode) {
            // Give specialized error message, since this type spec used to
            // be optional in the first FlatBuffers release.
            if (!p.is(':')) {
                return p.err("must specify the underlying integer type for this" ++
                    " enum (e.g. \': short\', which was the default).", .{});
            } else {
                try p.next();
            }
            // Specify the integer type underlying this enum.
            try p.parseType(&enum_def.underlying_type);
            if (!enum_def.underlying_type.base_type.isInteger() or
                enum_def.underlying_type.base_type.isBool())
                return p.err("underlying enum type must be integral", .{});
            // Make this type refer back to the enum it was derived from.
            enum_def.underlying_type.enum_def = enum_def;
        }
        try p.parseMetaData(&enum_def.base.attributes);

        const underlying_type = enum_def.underlying_type.base_type;
        if (enum_def.base.attributes.lookup("bit_flags") != null and
            !underlying_type.isUnsigned())
            // todo: Convert to the Error in the future?
            try p.warn("underlying type of bit_flags enum must be unsigned", .{});

        if (enum_def.base.attributes.lookup("force_align") != null)
            return p.err("`force_align` is not a valid attribute for Enums. ", .{});

        var evb = EnumValBuilder.init(p, enum_def);
        try p.expect('{');
        // A lot of code generatos expect that an enum is not-empty.
        if ((is_union or p.is('}')) and !p.opts.proto_mode) {
            _ = try evb.createEnumerator(p.alloc, "NONE");
            try evb.acceptEnumerator_();
        }
        const UnionType = struct { BaseType, ?*StructDef };
        var union_types = std.AutoHashMapUnmanaged(UnionType, void){};
        while (!p.is('}')) {
            if (p.opts.proto_mode and mem.eql(u8, p.state.attribute_.items, "option")) {
                todo("parseProtoOption", .{});
            } else {
                var ev = try evb.createEnumerator(p.alloc, try p.state.attribute_.toOwnedSlice(p.alloc));
                var full_name = std.ArrayList(u8).init(p.alloc);
                try full_name.appendSlice(ev.name);
                ev.doc_comment = p.state.doc_comment_;
                try p.expect(Token.Identifier.int());

                std.log.debug("full_name='{s}' is_union={}", .{ full_name.items, is_union });
                if (is_union) {
                    try p.parseNamespacing(&full_name, &ev.name);
                    if (p.opts.union_value_namespacing) {
                        // Since we can't namespace the actual enum identifiers, turn
                        // namespace parts into part of the identifier.
                        mem.replaceScalar(u8, full_name.items, '.', '_');
                        ev.name = try full_name.toOwnedSlice();
                    }
                    if (p.is(':')) {
                        try p.next();
                        try p.parseType(&ev.union_type);
                        if (ev.union_type.base_type != .STRUCT and
                            ev.union_type.base_type != .STRING)
                            return p.err("union value type may only be table/struct/string", .{});
                    } else {
                        std.log.debug("setting ev.union_type ", .{});
                        ev.union_type = Type.init(.STRUCT, try p.lookupCreateStruct(try full_name.toOwnedSlice(), .{}), null, 0);
                    }
                    if (!enum_def.uses_multiple_type_instances) {
                        const ut = UnionType{ ev.union_type.base_type, ev.union_type.struct_def };
                        try union_types.put(p.alloc, ut, {});
                        enum_def.uses_multiple_type_instances = ut[1] == null;
                    }
                }

                if (p.is('=')) {
                    try p.next();
                    try evb.assignEnumeratorValue(try p.state.attribute_.toOwnedSlice(p.alloc));
                    try p.expect(Token.IntegerConstant.int());
                }

                if (p.opts.proto_mode and p.is('[')) {
                    try p.next();
                    // ignore attributes on enums.
                    while (p.state.token_ != ']') try p.next();
                    try p.next();
                } else {
                    // parse attributes in fbs schema
                    try p.parseMetaData(&ev.attributes);
                }

                try evb.acceptEnumerator_();
            }
            if (!p.is(if (p.opts.proto_mode) ';' else ',')) break;
            try p.next();
        }
        try p.expect('}');

        // At this point, the enum can be empty if input is invalid proto-file.
        if (enum_def.size() == 0)
            return p.err("incomplete enum declaration, values not found", .{});

        if (enum_def.base.attributes.lookup("bit_flags") != null) {
            const base_width = @as(u64, 8 * underlying_type.sizeOf());
            for (enum_def.vals.vec.items) |it| {
                const u = it.getAsUInt64();
                // Stop manipulations with the sign.
                if (!underlying_type.isUnsigned() and u == (base_width - 1))
                    return p.err("underlying type of bit_flags enum must be unsigned", .{});
                if (u >= base_width)
                    return p.err("bit flag out of range of underlying integral type", .{});
                enum_def.changeEnumValue(it, @as(u64, 1) << @intCast(u6, u));
            }
        }

        enum_def.sortByValue(); // Must be sorted to use MinValue/MaxValue.

        // Ensure enum value uniqueness.
        const prev_it = enum_def.vals.vec.items.ptr;
        const end = prev_it + enum_def.vals.vec.items.len;
        var it = prev_it + 1;
        while (it != end) : (it += 1) {
            const prev_ev = prev_it[0];
            const ev = it[0];
            if (prev_ev.getAsUInt64() == ev.getAsUInt64())
                return p.err(
                    "all enum values must be unique: {s} and {s} are both {}",
                    .{ prev_ev.name, ev.name, ev.getAsInt64() },
                );
        }

        if (dest != null) dest.?.* = enum_def;
        const qualified_name =
            try p.current_namespace_.?.getFullyQualifiedName(p.alloc, enum_def.base.name, .{});
        const newtype = try p.alloc.create(Type);
        newtype.* = Type.init(.UNION, null, enum_def, 0);
        if (try p.types_.add(p.alloc, qualified_name, newtype))
            return p.err("datatype already exists: {s}", .{qualified_name});
    }

    fn doParse(
        p: *Parser,
        source: []const u8,
        include_paths_: []const []const u8,
        source_filename: []const u8,
        include_filename: []const u8,
    ) !void {
        std.log.debug(">>> doParse() {s}:{}", .{ source_filename, p.state.line_ });
        defer std.log.debug("<<< doParse() {s}:{}", .{ source_filename, p.state.line_ });
        var source_hash: u64 = 0;
        if (source_filename.len > 0) {
            // If the file is in-memory, don't include its contents in the hash as we
            // won't be able to load them later.
            source_hash = if (util.fileExists(source_filename))
                util.hashFile(source_filename, source)
            else
                util.hashFile(source_filename, "");

            if (p.included_files_.get(source_hash) == null) {
                try p.included_files_.put(p.alloc, source_hash, include_filename);
                try p.files_included_per_file_.put(p.alloc, source_filename, .{});
            } else {
                return;
            }
        }
        var include_paths = include_paths_;
        // if (include_paths.len == 0) {
        //   static const char *current_directory[] = { "", null };
        //   include_paths = current_directory;
        // }
        p.field_stack_.clearRetainingCapacity();
        p.builder_.clear();
        // Start with a blank namespace just in case this file doesn't have one.
        p.current_namespace_ = p.empty_namespace_;

        try p.startParseFile(source, source_filename);

        // Includes must come before type declarations:
        while (true) {
            // Parse pre-include proto statements if any:
            if (p.opts.proto_mode and
                (mem.eql(u8, p.state.attribute_.items, "option") or
                mem.eql(u8, p.state.attribute_.items, "syntax") or
                mem.eql(u8, p.state.attribute_.items, "package")))
            {
                todo("ParseProtoDecl", .{});
            } else if (p.isIdent("native_include")) {
                try p.next();
                try p.native_included_files_.append(p.alloc, try p.state.attribute_.toOwnedSlice(p.alloc));
                try p.expect(Token.StringConstant.int());
                try p.expect(';');
            } else if (p.isIdent("include") or (p.opts.proto_mode and p.isIdent("import"))) {
                try p.next();
                if (p.opts.proto_mode and mem.eql(u8, p.state.attribute_.items, "public")) try p.next();
                const name = util.posixPath(try p.state.attribute_.toOwnedSlice(p.alloc));
                try p.expect(Token.StringConstant.int());
                // Look for the file relative to the directory of the current file.
                var filepath: []const u8 = "";
                if (source_filename.len != 0) {
                    const source_file_directory =
                        util.stripFileName(source_filename);
                    filepath = try util.concatPathFileName(p.alloc, source_file_directory, name);
                }
                if (filepath.len == 0 or !util.fileExists(filepath)) {
                    // Look for the file in include_paths.
                    // for (auto paths = include_paths; paths and *paths; paths++) {
                    for (include_paths) |paths| {
                        p.alloc.free(filepath);
                        std.log.debug("incpath '{s}'", .{paths});
                        filepath = try util.concatPathFileName(p.alloc, paths, name);
                        if (util.fileExists(filepath)) break;
                    } else {
                        p.alloc.free(filepath);
                        filepath.len = 0;
                    }
                }
                std.log.debug("filepath {s} name {s}", .{ filepath, name });
                if (filepath.len == 0)
                    return p.err("unable to locate include file: {s}", .{name});
                if (source_filename.len != 0) {
                    const included_file = IncludedFile{
                        .filename = filepath,
                        .schema_name = name,
                    };
                    const gop = try p.files_included_per_file_.getOrPut(p.alloc, source_filename);
                    if (!gop.found_existing) gop.value_ptr.* = .{};
                    try gop.value_ptr.put(p.alloc, included_file, {});
                }
                const contents = util.loadFile(p.alloc, filepath) catch |e|
                    return p.err("unable to load include file: {s} {s}", .{ name, @errorName(e) });
                if (p.included_files_.get(util.hashFile(filepath, contents)) == null) {
                    std.log.debug("parsing include file '{s}'", .{filepath});
                    // We found an include file that we have not parsed yet.
                    // Parse it.
                    try p.doParse(contents, include_paths, filepath, name);
                    // We generally do not want to output code for any included files:
                    if (!p.opts.generate_all) p.markGenerated();
                    // Reset these just in case the included file had them, and the
                    // parent doesn't.
                    p.root_struct_def_ = null;
                    p.file_identifier_.len = 0;
                    p.file_extension_.len = 0;
                    // This is the easiest way to continue this file after an include:
                    // instead of saving and restoring all the state, we simply start the
                    // file anew. This will cause it to encounter the same include
                    // statement again, but this time it will skip it, because it was
                    // entered into included_files_.
                    // This is recursive, but only go as deep as the number of include
                    // statements.
                    _ = p.included_files_.remove(source_hash);
                    return p.doParse(source, include_paths, source_filename, include_filename);
                } else std.log.debug("skipping already parsed include file '{s}'", .{filepath});
                try p.expect(';');
            } else {
                break;
            }
        }
        // Now parse all other kinds of declarations:
        while (p.state.token_ != Token.Eof.int()) {
            // std.log.debug("doParse token '{s}':{}", .{ Token.toStr(p.state.token_, &p.buf_one), p.state.token_ });
            if (p.opts.proto_mode) {
                todo("ParseProtoDecl()", .{});
            } else if (p.isIdent("namespace")) {
                try p.parseNamespace();
            } else if (p.state.token_ == '{') {
                return;
            } else if (p.isIdent("enum")) {
                try p.parseEnum(false, null, source_filename);
            } else if (p.isIdent("union")) {
                try p.parseEnum(true, null, source_filename);
            } else if (p.isIdent("root_type")) {
                try p.next();
                var root_type = std.ArrayList(u8).init(p.alloc);
                try root_type.appendSlice(p.state.attribute_.items);
                try p.expect(Token.Identifier.int());
                var out: []const u8 = "";
                try p.parseNamespacing(&root_type, &out);
                if (p.opts.root_type.len == 0) {
                    if (!try p.setRootType(root_type.items))
                        return p.err("unknown root type: {s}", .{root_type.items});
                    if (p.root_struct_def_.?.fixed)
                        return p.err("root type must be a table", .{});
                }
                try p.expect(';');
            } else if (p.isIdent("file_identifier")) {
                try p.next();
                p.file_identifier_ = try p.state.attribute_.toOwnedSlice(p.alloc);
                try p.expect(Token.StringConstant.int());
                if (p.file_identifier_.len != base.file_identifier_length)
                    return p.err(
                        "file_identifier must be exactly {} characters",
                        .{base.file_identifier_length},
                    );
                try p.expect(';');
            } else if (p.isIdent("file_extension")) {
                try p.next();
                p.file_extension_ = try p.state.attribute_.toOwnedSlice(p.alloc);
                try p.expect(Token.StringConstant.int());
                try p.expect(';');
            } else if (p.isIdent("include")) {
                return p.err("includes must come before declarations", .{});
            } else if (p.isIdent("attribute")) {
                try p.next();
                const name = try p.state.attribute_.toOwnedSlice(p.alloc);
                if (p.is(Token.Identifier.int())) {
                    try p.next();
                } else {
                    try p.expect(Token.StringConstant.int());
                }
                try p.expect(';');
                try p.known_attributes_.put(p.alloc, name, false);
            } else if (p.isIdent("rpc_service")) {
                try p.parseService(source_filename);
            } else {
                try p.parseDecl(source_filename);
            }
        }
        try p.expect(Token.Eof.int());
        if (p.opts.warnings_as_errors and p.has_warning_) {
            return p.err("treating warnings as errors, failed due to above warnings", .{});
        }
    }

    /// Parses exactly nibbles worth of hex digits into a number, or error.
    fn parseHexNum(p: *Parser, nibbles: u8, val: *u64) !void {
        assert(nibbles > 0);
        // for (int i = 0; i < nibbles; i++)
        var i: u8 = 0;
        while (i < nibbles) : (i += 1) {
            if (!std.ascii.isHex(p.state.cursor_[i]))
                return p.err("escape code must be followed by {} hex digits", .{nibbles});
        }
        // std::string target(cursor_, cursor_ + nibbles);
        const target = p.state.cursor_[0..nibbles];
        val.* = try std.fmt.parseUnsigned(u64, target, 16);
        p.state.cursor_ += nibbles;
    }

    pub fn skipByteOrderMark(p: *Parser) !void {
        if (p.state.cursor_[0] != 0xef) return;
        p.state.cursor_ += 1;
        if (p.state.cursor_[0] != 0xbb)
            return p.err("invalid utf-8 byte order mark", .{});
        p.state.cursor_ += 1;
        if (p.state.cursor_[0] != 0xbf)
            return p.err("invalid utf-8 byte order mark", .{});
        p.state.cursor_ += 1;
    }

    pub const Token = enum(i32) {
        Eof = 256,
        StringConstant = 257,
        IntegerConstant = 258,
        FloatConstant = 259,
        Identifier = 260,
        _,

        pub fn int(t: Token) i32 {
            return @enumToInt(t);
        }
        pub fn toStr(t: i32, buf: *[1]u8) []const u8 {
            if (t > 255) return switch (@intToEnum(Token, t)) {
                .Eof => "Eof",
                .StringConstant => "StringConstant",
                .IntegerConstant => "IntegerConstant",
                .FloatConstant => "FloatConstant",
                .Identifier => "Identifier",
                else => unreachable,
            } else {
                buf[0] = @intCast(u8, t);
                return buf;
            }
        }
    };

    fn is(p: *Parser, t: i32) bool {
        return t == p.state.token_;
    }

    fn next(p: *Parser) !void {
        p.state.doc_comment_.clearRetainingCapacity();
        p.state.prev_cursor_ = p.state.cursor_;
        var seen_newline = p.state.cursor_ == p.source_.ptr;
        p.state.attribute_.items.len = 0;
        p.state.attr_is_trivial_ascii_string_ = true;
        while (true) {
            var c = p.state.cursor_[0];
            p.state.cursor_ += 1;
            p.state.token_ = c;
            // std.log.debug("next() '{c}'", .{c});
            switch (c) {
                0 => {
                    p.state.cursor_ -= 1;
                    p.state.token_ = Token.Eof.int();
                    return;
                },
                ' ', '\r', '\t' => continue,
                '\n' => {
                    p.state.markNewLine();
                    seen_newline = true;
                    continue;
                },
                '{', '}', '(', ')', '[', ']', '<', '>', ',', ':', ';', '=' => return,
                '\"', '\'' => {
                    var unicode_high_surrogate: i32 = -1;

                    while (p.state.cursor_[0] != c) {
                        if (p.state.cursor_[0] < ' ' and @intCast(i8, p.state.cursor_[0]) >= 0)
                            return p.err("illegal character in string constant", .{});
                        if (p.state.cursor_[0] == '\\') {
                            p.state.attr_is_trivial_ascii_string_ = false; // has escape sequence
                            p.state.cursor_ += 1;
                            if (unicode_high_surrogate != -1 and p.state.cursor_[0] != 'u') {
                                return p.err("illegal Unicode sequence (unpaired high surrogate)", .{});
                            }
                            switch (p.state.cursor_[0]) {
                                'n' => {
                                    try p.state.attribute_.append(p.alloc, '\n');
                                    p.state.cursor_ += 1;
                                },
                                't' => {
                                    try p.state.attribute_.append(p.alloc, '\t');
                                    p.state.cursor_ += 1;
                                },
                                'r' => {
                                    try p.state.attribute_.append(p.alloc, '\r');
                                    p.state.cursor_ += 1;
                                },
                                'b' => {
                                    p.state.attribute_.append(p.alloc, unreachable); // '\b');
                                    p.state.cursor_ += 1;
                                },
                                'f' => {
                                    p.state.attribute_.append(p.alloc, unreachable); // '\f');
                                    p.state.cursor_ += 1;
                                },
                                '\"' => {
                                    try p.state.attribute_.append(p.alloc, '\"');
                                    p.state.cursor_ += 1;
                                },
                                '\'' => {
                                    try p.state.attribute_.append(p.alloc, '\'');
                                    p.state.cursor_ += 1;
                                },
                                '\\' => {
                                    try p.state.attribute_.append(p.alloc, '\\');
                                    p.state.cursor_ += 1;
                                },
                                '/' => {
                                    try p.state.attribute_.append(p.alloc, '/');
                                    p.state.cursor_ += 1;
                                },
                                'x' => { // Not in the JSON standar,
                                    p.state.cursor_ += 1;
                                    var val: u64 = undefined;
                                    try p.parseHexNum(2, &val);
                                    try p.state.attribute_.append(p.alloc, @intCast(u8, val));
                                },
                                'u' => {
                                    p.state.cursor_ += 1;
                                    var val: u64 = undefined;
                                    try p.parseHexNum(4, &val);
                                    if (val >= 0xD800 and val <= 0xDBFF) {
                                        if (unicode_high_surrogate != -1)
                                            return p.err("illegal Unicode sequence (multiple high surrogates)", .{})
                                        else
                                            unicode_high_surrogate = @intCast(i32, val);
                                    } else if (val >= 0xDC00 and val <= 0xDFFF) {
                                        if (unicode_high_surrogate == -1)
                                            return p.err("illegal Unicode sequence (unpaired low surrogate)", .{})
                                        else {
                                            var code_point: i32 = @as(i32, 0x10000) +
                                                ((unicode_high_surrogate & 0x03FF) << 10) +
                                                @intCast(i32, val & 0x03FF);
                                            _ = util.ToUTF8(
                                                @intCast(u21, code_point),
                                                try p.state.attribute_.toOwnedSlice(p.alloc),
                                            );
                                            unicode_high_surrogate = -1;
                                        }
                                    } else {
                                        if (unicode_high_surrogate != -1) {
                                            return p.err("illegal Unicode sequence (unpaired high surrogate)", .{});
                                        }
                                        _ = util.ToUTF8(
                                            @intCast(u21, val),
                                            try p.state.attribute_.toOwnedSlice(p.alloc),
                                        );
                                    }
                                },
                                else => return p.err("unknown escape code in string constant", .{}),
                            }
                        } else { // printable chars + UTF-8 bytes
                            if (unicode_high_surrogate != -1) {
                                return p.err("illegal Unicode sequence (unpaired high surrogate)", .{});
                            }
                            // reset if non-printable
                            p.state.attr_is_trivial_ascii_string_ = p.state.attr_is_trivial_ascii_string_ and
                                util.check_ascii_range(p.state.cursor_[0], ' ', '~');
                            try p.state.attribute_.append(p.alloc, p.state.cursor_[0]);
                            p.state.cursor_ += 1;
                        }
                    }
                    if (unicode_high_surrogate != -1) {
                        return p.err("illegal Unicode sequence (unpaired high surrogate)", .{});
                    }
                    p.state.cursor_ += 1;
                    if (!p.state.attr_is_trivial_ascii_string_ and !p.opts.allow_non_utf8 and
                        !std.unicode.utf8ValidateSlice(p.state.attribute_.items))
                        return p.err("illegal UTF-8 sequence", .{});

                    p.state.token_ = Token.StringConstant.int();
                    std.log.debug(
                        "strlit '{s}' cursor '{c}'",
                        .{ p.state.attribute_.items, p.state.cursor_[0] },
                    );
                    return;
                },
                '/' => {
                    if (p.state.cursor_[0] == '/') {
                        p.state.cursor_ += 1;
                        const start = p.state.cursor_;
                        while (p.state.cursor_[0] != 0 and p.state.cursor_[0] != '\n' and
                            p.state.cursor_[0] != '\r')
                            p.state.cursor_ += 1;
                        if (start[0] == '/') { // documentation comment
                            if (!seen_newline)
                                return p.err("a documentation comment should be on a line on its own", .{});
                            try p.state.doc_comment_.append(p.alloc, strFromRange(start + 1, p.state.cursor_));
                        }
                    } else if (p.state.cursor_[0] == '*') {
                        p.state.cursor_ += 1;
                        // TODO: make nested.
                        while (p.state.cursor_[0] != '*' or p.state.cursor_[1] != '/') {
                            if (p.state.cursor_[0] == '\n') p.state.markNewLine();
                            if (p.state.cursor_[0] == 0) return p.err("end of file in comment", .{});
                            p.state.cursor_ += 1;
                        }
                        p.state.cursor_ += 2;
                    }
                    // fall through
                },
                else => {}, // 'fall through'
            }
            // std.log.debug("isIdentifierStart({c}) {}", .{ c, isIdentifierStart(c) });
            if (isIdentifierStart(c)) {
                // Collect all chars of an identifier:
                // const char *start = p.state.cursor_ - 1;
                const start = p.state.cursor_ - 1;
                while (isIdentifierStart(p.state.cursor_[0]) or std.ascii.isDigit(p.state.cursor_[0]))
                    p.state.cursor_ += 1;
                try p.state.attribute_.appendSlice(p.alloc, strFromRange(start, p.state.cursor_));
                p.state.token_ = Token.Identifier.int();
                return;
            }

            const has_sign = (c == '+') or (c == '-');
            if (has_sign) {
                // Check for +/-inf which is considered a float constant.
                if (mem.eql(u8, p.state.cursor_[0..3], "inf") and
                    !(isIdentifierStart(p.state.cursor_[3]) or std.ascii.isDigit(p.state.cursor_[3])))
                {
                    p.state.attribute_.items.len = 0;
                    try p.state.attribute_.appendSlice(p.alloc, strFromRange(p.state.cursor_ - 1, p.state.cursor_ + 3));
                    p.state.token_ = Token.FloatConstant.int();
                    p.state.cursor_ += 3;
                    return;
                }

                if (isIdentifierStart(p.state.cursor_[0])) {
                    // '-'/'+' and following identifier - it could be a predefined
                    // constant. Return the sign inp.state.token_, see ParseSingleValue.
                    return;
                }
            }

            var dot_lvl: i32 =
                if (c == '.') 0 else 1; // dot_lvl==0 <=> exactly one '.' seen
            if (dot_lvl == 0 and !std.ascii.isDigit(p.state.cursor_[0])) return; // enum?
            // Parser accepts hexadecimal-floating-literal (see C++ 5.13.4).
            if (std.ascii.isDigit(c) or has_sign or dot_lvl == 0) {
                const start = p.state.cursor_ - 1;
                var start_digits = if (!std.ascii.isDigit(c))
                    p.state.cursor_
                else
                    p.state.cursor_ - 1;
                if (!std.ascii.isDigit(c) and std.ascii.isDigit(p.state.cursor_[0])) {
                    start_digits = p.state.cursor_; // see digit in p.state.cursor_ position
                    c = p.state.cursor_[0];
                    p.state.cursor_ += 1;
                }
                // hex-float can't begind with '.'
                const use_hex = dot_lvl != 0 and (c == '0') and
                    util.isAlphaChar(p.state.cursor_[0], 'X');
                if (use_hex) {
                    p.state.cursor_ += 1;
                    start_digits = p.state.cursor_; // '0x' is the prefix, skip it
                }
                // Read an integer number or mantisa of float-point number.
                while (true) {
                    if (use_hex) {
                        while (std.ascii.isHex(p.state.cursor_[0])) p.state.cursor_ += 1;
                    } else {
                        while (std.ascii.isDigit(p.state.cursor_[0])) p.state.cursor_ += 1;
                    }
                    const proceed = ((p.state.cursor_[0] == '.') and blk: {
                        p.state.cursor_ += 1;
                        break :blk true;
                    } and blk: {
                        dot_lvl -= 1;
                        break :blk dot_lvl >= 0;
                    });
                    if (!proceed) break;
                }

                // Exponent of float-point number.
                if ((dot_lvl >= 0) and util.ptrGreater(p.state.cursor_, start_digits)) {
                    // The exponent suffix of hexadecimal float number is mandatory.
                    if (use_hex and dot_lvl == 0) start_digits = p.state.cursor_;
                    if ((use_hex and util.isAlphaChar(p.state.cursor_[0], 'P')) or
                        util.isAlphaChar(p.state.cursor_[0], 'E'))
                    {
                        dot_lvl = 0; // Emulate dot to signal about float-point number.
                        p.state.cursor_ += 1;
                        if (p.state.cursor_[0] == '+' or p.state.cursor_[0] == '-')
                            p.state.cursor_ += 1;
                        start_digits = p.state.cursor_; // the exponent-part has to have digits
                        // Exponent is decimal integer number
                        while (std.ascii.isDigit(p.state.cursor_[0])) p.state.cursor_ += 1;
                        if (p.state.cursor_[0] == '.') {
                            p.state.cursor_ += 1; // If see a dot treat it as part of invalid number.
                            dot_lvl = -1; // Fall thru to err()
                        }
                    }
                }
                // Finalize.
                if ((dot_lvl >= 0) and
                    util.ptrGreater(p.state.cursor_, start_digits))
                {
                    try p.state.attribute_.appendSlice(
                        p.alloc,
                        strFromRange(start, p.state.cursor_),
                    );
                    p.state.token_ = if (dot_lvl != 0)
                        Token.IntegerConstant.int()
                    else
                        Token.FloatConstant.int();
                    return;
                } else {
                    return p.err(
                        "invalid number: {s}",
                        .{strFromRange(start, p.state.cursor_)},
                    );
                }
            }
            // std.log.debug("c={c}:{}", .{ c, c });
            if (false == util.check_ascii_range(c, ' ', '~'))
                return p.err("illegal character: code: {}", .{c});
        }
    }

    fn message(p: *Parser, comptime fmt: []const u8, args: anytype) !void {
        // log all warnings and errors
        if (p.error_.items.len != 0) try p.error_.append(p.alloc, '\n');
        const has_file = p.file_being_parsed_.len != 0;

        if (has_file) try p.error_.appendSlice(
            p.alloc,
            try std.fs.realpath(p.file_being_parsed_, &p.path_buf),
        );

        const writer = p.error_.writer(p.alloc);
        if (builtin.os.tag == .windows) {
            try writer.print("({}, {})", .{ p.state.line_, p.state.cursorPosition() });
        } else {
            const colon = if (has_file) ":" else "";
            try writer.print("{s}{}: {}", .{ colon, p.state.line_, p.state.cursorPosition() });
        }
        try writer.print(": " ++ fmt, args);
    }

    pub const ParseError = error{ ParserError, FileSystem, NotSupported } ||
        mem.Allocator.Error ||
        std.fs.File.ReadError ||
        std.fs.File.OpenError ||
        std.os.AccessError;

    fn err(p: *Parser, comptime fmt: []const u8, args: anytype) ParseError {
        try p.message("error: " ++ fmt, args);
        if (true) {
            std.log.debug("{s}", .{p.error_.items});
            unreachable;
        }
        return error.ParserError;
    }
    fn warn(p: *Parser, comptime fmt: []const u8, args: anytype) !void {
        if (!p.opts.no_warnings) {
            try p.message("warning: " ++ fmt, args);
        }
    }

    fn startParseFile(
        p: *Parser,
        source: []const u8,
        source_filename: []const u8,
    ) !void {
        p.file_being_parsed_ = source_filename;
        p.source_ = source;
        p.state.resetState(p.source_);
        p.error_.clearRetainingCapacity();
        try p.skipByteOrderMark();
        try next(p);
        if (is(p, Token.Eof.int()))
            return p.err("input file is empty", .{});
    }

    pub fn parseRoot(
        p: *Parser,
        source: []const u8,
        include_paths: []const []const u8,
        source_filename: []const u8,
    ) !void {
        try doParse(p, source, include_paths, source_filename, "");
        // Check that all types were defined.
        for (p.structs_.vec.items) |it| {
            const struct_def = it.*;
            if (struct_def.predecl) {
                if (p.opts.proto_mode) {
                    if (true) todo("proto_mode", .{});
                    // Protos allow enums to be used before declaration, so check if that
                    // is the case here.
                    var enum_def: ?*EnumDef = null;
                    var components: usize = struct_def.defined_namespace.components.items.len + 1;
                    while (components != 0 and enum_def == null) : (components -= 1) {
                        const qualified_name =
                            struct_def.defined_namespace.getFullyQualifiedName(struct_def.name, components - 1);
                        enum_def = p.lookupEnum(qualified_name);
                    }
                    if (enum_def != null) {
                        // This is pretty slow, but a simple solution for now.
                        const initial_count = struct_def.refcount;
                        for (p.structs_.vec.items) |struct_it| {
                            const sd = struct_it.*;
                            for (sd.fields.vec.items) |field_it| {
                                const field = field_it.*;
                                if (field.value.type.struct_def == &struct_def) {
                                    field.value.type.struct_def = null;
                                    field.value.type.enum_def = enum_def;
                                    var bt = if (field.value.type.isVector())
                                        field.value.type.element
                                    else
                                        field.value.type.base_type;
                                    assert(bt == .STRUCT);
                                    bt = enum_def.underlying_type.base_type;
                                    struct_def.refcount -= 1;
                                    enum_def.refcount += 1;
                                }
                            }
                        }
                        if (struct_def.refcount != 0)
                            return p.err("internal: {}/{} use(s) of pre-declaration enum not accounted for: {s}", .{ struct_def.refcount, initial_count, enum_def.name });
                        p.structs_.dict.remove(p.structs_.dict.find(struct_def.name));
                        it = p.structs_.vec.remove(it);
                        p.alloc.destroy(struct_def);
                        continue; // Skip error.
                    }
                }
                if (struct_def.original_location.len != 0)
                    return p.err("type referenced but not defined (check namespace): {s}", .{struct_def.base.name});
            }
        }

        // This check has to happen here and not earlier, because only now do we
        // know for sure what the type of these are.
        // for (auto it = enums_.vec.begin(); it != enums_.vec.end(); ++it) {
        for (p.enums_.vec.items) |it| {
            const enum_def = it.*;
            if (enum_def.is_union) {
                for (enum_def.vals.vec.items) |val_it| {
                    const val = val_it.*;
                    if (!(p.opts.lang_to_generate.count() != 0 and
                        p.supportsAdvancedUnionFeatures()) and
                        (val.union_type.isStruct() or val.union_type.isString()))
                        return p.err("only tables can be union elements in" ++
                            " the generated language: {s}", .{val.name});
                }
            }
        }

        try p.checkPrivateLeak();

        // Parse JSON object only if the scheme has been parsed.
        if (p.state.token_ == '{')
            todo("doParseJson()", .{});
    }
    fn checkPrivateLeak(p: *Parser) !void {
        if (!p.opts.no_leak_private_annotations) return;
        // Iterate over all structs/tables to validate we arent leaking
        // any private (structs/tables/enums)
        for (p.structs_.vec.items) |it| {
            const struct_def = it.*;
            for (struct_def.fields.vec.items) |fld_it| {
                const field = fld_it.*;

                if (field.value.type.enum_def != null) {
                    try p.checkPrivatelyLeakedFields(
                        struct_def.base,
                        field.value.type.enum_def.?.base,
                    );
                } else if (field.value.type.struct_def != null) {
                    try p.checkPrivatelyLeakedFields(
                        struct_def.base,
                        field.value.type.struct_def.?.base,
                    );
                }
            }
        }
        // Iterate over all enums to validate we arent leaking
        // any private (structs/tables)
        for (p.enums_.vec.items) |it| {
            const enum_def = it.*;
            if (enum_def.is_union) {
                for (enum_def.vals.vec.items) |val_it| {
                    const val = val_it.*;
                    if (val.union_type.struct_def != null) {
                        try p.checkPrivatelyLeakedFields(
                            enum_def.base,
                            val.union_type.struct_def.?.base,
                        );
                    }
                }
            }
        }
    }

    fn checkPrivatelyLeakedFields(p: *Parser, def: Definition, value_type: Definition) !void {
        if (!p.opts.no_leak_private_annotations) return;
        const is_private = def.attributes.lookup("private");
        const is_field_private = value_type.attributes.lookup("private");
        if (is_private == null and is_field_private != null) {
            return p.err("Leaking private implementation, verify all objects have similar " ++
                "annotations", .{});
        }
    }

    pub fn parse(
        p: *Parser,
        source: []const u8,
        include_paths: []const []const u8,
        source_filename: []const u8,
    ) !void {
        // const initial_depth = parse_depth_counter_;
        if (p.opts.use_flexbuffers) {
            // ParseFlexBuffer(source, source_filename, &flex_builder_);
            todo("ParseFlexBuffer", .{});
        } else {
            try parseRoot(p, source, include_paths, source_filename);
        }
        // assert(initial_depth == parse_depth_counter_);
    }
};
