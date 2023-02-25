const std = @import("std");
const mem = std.mem;
const util = @import("util.zig");
const common = @import("common.zig");
const todo = common.todo;
const Case = util.Case;
const CaseTx = util.CaseTransform;
const Namer = @This();

config_: Config,
pub fn init(
    config_: Config,
) Namer {
    return .{
        .config_ = config_,
    };
}

// virtual std::string EscapeKeyword(const std::string &name) const {
//   if (keywords_.find(name) == keywords_.end()) {
//     return name;
//   } else {
//     return config_.keyword_prefix + name + config_.keyword_suffix;
//   }
// }
pub fn escapeKeyword(_: Namer, name: []const u8, writer: anytype) !void {
    // TODO: make keywords generic
    if (std.zig.Token.keywords.get(name) == null) {
        _ = try writer.write(name);
    } else {
        // return n.config_.keyword_prefix + name + config_.keyword_suffix;
        todo("escapeKeyword({s})", .{name});
    }
}

// virtual std::string Format(const std::string &s, Case casing) const {
//     if (config_.escape_keywords == Config::Escape::BeforeConvertingCase) {
//       return ConvertCase(EscapeKeyword(s), casing, Case::kLowerCamel);
//     } else {
//       return EscapeKeyword(ConvertCase(s, casing, Case::kLowerCamel));
//     }
//   }
pub fn format(n: Namer, s: []const u8, casing: Case, writer: anytype) !void {
    return if (n.config_.escape_keywords == .BeforeConvertingCase)
        util.convertCase(s, CaseTx.init(casing, .LowerCamel), writer)
    else
        // n.escapeKeyword(try util.convertCase(s, CaseTx.init(casing, .LowerCamel), writer));
        todo("escape_keywords == .AfterConvertingCase", .{});
}

// virtual std::string Namespace(const std::string &s) const {
//   return Format(s, config_.namespaces);
// }

// virtual std::string Namespace(const std::vector<std::string> &ns) const {
//   std::string result;
//   for (auto it = ns.begin(); it != ns.end(); it++) {
//     if (it != ns.begin()) result += config_.namespace_seperator;
//     result += Namespace(*it);
//   }
//   return result;
// }

pub fn namespace(n: Namer, s: []const u8, writer: anytype) !void {
    // todo("namespace", .{});
    return n.format(s, n.config_.namespaces, writer);
    // _ = writer;
    // _ = n;
    // return s;
}
pub fn namespace2(_: Namer, _: []const []const u8) []const u8 {
    todo("namespace2", .{});
}

// Returns `filename` with the right casing, suffix, and extension.
// virtual std::string File(const std::string &filename,
//                          SkipFile skips = SkipFile::None) const {
//   const bool skip_suffix = (skips & SkipFile::Suffix) != SkipFile::None;
//   const bool skip_ext = (skips & SkipFile::Extension) != SkipFile::None;
//   return ConvertCase(filename, config_.filenames, Case::kUpperCamel) +
//          (skip_suffix ? "" : config_.filename_suffix) +
//          (skip_ext ? "" : config_.filename_extension);
// }
/// Returns `filename` with the right casing, suffix, and extension.
pub fn file(n: Namer, alloc: mem.Allocator, filename: []const u8, skips_: []const SkipFile) ![3][]const u8 {
    var skips = Skips.initEmpty();
    for (skips_) |s| skips.insert(s);
    return .{
        try util.convertCase(alloc, filename, n.config_.filenames, Case.UpperCamel),
        (if (skips.contains(.Suffix)) "" else n.config_.filename_suffix),
        (if (skips.contains(.Extension)) "" else n.config_.filename_extension),
    };
}

pub const Skips = std.enums.EnumSet(SkipFile);
// Options for Namer::File.
pub const SkipFile = enum(u2) {
    None = 0,
    Suffix = 1,
    Extension = 2,
    SuffixAndExtension = 3,
};

pub const Config = struct {
    // Symbols in code.

    // Case style for flatbuffers-defined types.
    // e.g. `class TableA {}`
    types: Case,
    // Case style for flatbuffers-defined constants.
    // e.g. `uint64_t ENUM_A_MAX`;
    constants: Case,
    // Case style for flatbuffers-defined methods.
    // e.g. `class TableA { int field_a(); }`
    methods: Case,
    // Case style for flatbuffers-defined functions.
    // e.g. `TableA* get_table_a_root()`;
    functions: Case,
    // Case style for flatbuffers-defined fields.
    // e.g. `struct Struct { int my_field; }`
    fields: Case,
    // Case style for flatbuffers-defined variables.
    // e.g. `int my_variable = 2`
    variables: Case,
    // Case style for flatbuffers-defined variants.
    // e.g. `enum class Enum { MyVariant, }`
    variants: Case,
    // Seperator for qualified enum names.
    // e.g. `Enum::MyVariant` uses `::`.
    enum_variant_seperator: []const u8,

    // Configures, when formatting code, whether symbols are checked against
    // keywords and escaped before or after case conversion. It does not make
    // sense to do so before, but its legacy behavior. :shrug:
    // TODO(caspern): Deprecate.

    escape_keywords: Escape,

    // Namespaces

    // e.g. `namespace my_namespace {}`
    namespaces: Case,
    // The seperator between namespaces in a namespace path.
    namespace_seperator: []const u8,

    // Object API.
    // Native versions flatbuffers types have this prefix.
    // e.g. "" (it's usually empty string)
    object_prefix: []const u8,
    // Native versions flatbuffers types have this suffix.
    // e.g. "T"
    object_suffix: []const u8,

    // Keywords.
    // Prefix used to escape keywords. It is usually empty string.
    keyword_prefix: []const u8,
    // Suffix used to escape keywords. It is usually "_".
    keyword_suffix: []const u8,

    // Files.

    // Case style for filenames. e.g. `foo_bar_generated.rs`
    filenames: Case,
    // Case style for directories, e.g. `output_files/foo_bar/baz/`
    directories: Case,
    // The directory within which we will generate files.
    output_path: []const u8,
    // Suffix for generated file names, e.g. "_generated".
    filename_suffix: []const u8,
    // Extension for generated files, e.g. ".cpp" or ".rs".
    filename_extension: []const u8,

    pub const Escape = enum {
        BeforeConvertingCase,
        AfterConvertingCase,
    };
};
