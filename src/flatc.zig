const std = @import("std");
const mem = std.mem;
const idl_parser = @import("idl_parser.zig");
const Parser = idl_parser.Parser;
const StringList = std.ArrayListUnmanaged([]const u8);
const idl = @import("idl.zig");
const code_generator = @import("code_generator.zig");
const CodeGenerator = code_generator.CodeGenerator;
const fb = @import("flatbuffers");
const common = fb.common;
const todo = common.todo;
const util = @import("util.zig");
const posixPath = util.posixPath;
const stripFileName = util.stripFileName;

pub const WarnFn = @TypeOf(warn);
pub const ErrFn = @TypeOf(_err);

pub var program_name: ?[*:0]const u8 = null;

pub const WarnOpts = struct {
    show_exe: bool = false,

    pub fn init(
        show_exe: bool,
    ) WarnOpts {
        return .{
            .show_exe = show_exe,
        };
    }
};
fn warn(
    _: ?*const anyopaque,
    comptime fmt: []const u8,
    args: anytype,
    opts: WarnOpts,
) void {
    if (opts.show_exe) std.debug.print("{s}", .{program_name.?});
    std.debug.print("warning: " ++ fmt, args);
}

fn err(
    ptr: *const anyopaque,
    comptime fmt: []const u8,
    args: anytype,
) noreturn {
    _err(ptr, fmt, args, .{});
}

fn errWithUsage(
    ptr: *const anyopaque,
    comptime fmt: []const u8,
    args: anytype,
) void {
    _err(ptr, fmt, args, .{ .usage = true });
}

pub const ErrOpts = struct {
    usage: bool = true,
    show_exe: bool = false,

    pub fn init(
        usage: bool,
        show_exe: bool,
    ) ErrOpts {
        return .{
            .usage = usage,
            .show_exe = show_exe,
        };
    }
};

fn _err(
    ptr: *const anyopaque,
    comptime fmt: []const u8,
    args: anytype,
    opts: ErrOpts,
) noreturn {
    const flatc = common.ptrAlignCast(*const Compiler, ptr);
    if (opts.show_exe) std.debug.print("{s}", .{program_name.?});
    if (opts.usage) flatc.printShortUsageString();
    std.debug.print("error: " ++ fmt, args);
    std.os.exit(1);
}

pub const params: Compiler.InitParams = .{ .warn_fn = warn, .err_fn = _err };

pub const LangOptionsCtx = struct {
    pub fn hash(_: LangOptionsCtx, o: Option) u64 {
        return std.hash_map.hashString(o.long_opt);
    }
    pub fn eql(_: LangOptionsCtx, a: Option, b: Option) bool {
        return mem.eql(u8, a.long_opt, b.long_opt);
    }
};
pub var language_options: std.HashMapUnmanaged(Option, void, LangOptionsCtx, std.hash_map.default_max_load_percentage) = .{};

pub const Compiler = struct {
    params: *const InitParams,
    code_generators: CodeGeneratorMap = .{},
    allocator: mem.Allocator,
    buf: [256]u8 = undefined,

    pub const CodeGeneratorMap = std.StringHashMapUnmanaged(*CodeGenerator);

    pub const InitParams = struct {
        warn_fn: WarnFn,
        err_fn: ErrFn,
    };

    const GopResult = CodeGeneratorMap.GetOrPutResult;
    pub fn getOrPutCodeGenerator(
        flatc: *Compiler,
        prefix: []const u8,
        name: []const u8,
    ) !GopResult {
        const cg = try std.fmt.bufPrint(&flatc.buf, "{s}{s}", .{ prefix, name });
        return flatc.code_generators.getOrPut(flatc.allocator, cg);
    }
    pub fn parseFromCli(flatc: *Compiler, args: [][:0]u8) !Options {
        if (args.len <= 1) err(flatc, "Need to provide at least one argument.", .{});
        var options = Options{ .opts = .{} };
        options.program_name = args[0];
        var opts = &options.opts;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (arg[0] == '-') {
                if (mem.eql(u8, arg, "-I")) {
                    i += 1;
                    if (i >= args.len)
                        errWithUsage(flatc, "missing path following: {s}", .{arg});
                    try options.include_directories_storage.append(
                        flatc.allocator,
                        posixPath(args[i]),
                    );
                    try options.include_directories.append(
                        flatc.allocator,
                        options.include_directories_storage.getLast(),
                    );
                } else if (mem.eql(u8, arg, "-o")) {
                    i += 1;
                    if (i >= args.len)
                        errWithUsage(flatc, "missing path following: {s}", .{arg});
                    options.output_path = util.posixPath(args[i]);
                } else {
                    if (flatc.code_generators.get(arg)) |cg| {
                        options.any_generator = true;
                        opts.lang_to_generate.insert(cg.language);

                        const is_binary_schema = cg.supports_bfbs_generation;
                        opts.binary_schema_comments = is_binary_schema;
                        options.requires_bfbs = is_binary_schema;
                        try options.generators.append(flatc.allocator, cg);
                    } else {
                        errWithUsage(flatc, "unknown commandline argument: {s}", .{arg});
                        return options;
                    }
                }
            } else {
                try options.filenames.append(flatc.allocator, posixPath(arg));
            }
        }
        return options;
    }
    pub fn printShortUsageString(flatc: Compiler) void {
        _ = flatc;
        // todo("printShortUsageString", .{});
        std.debug.print("usage: TODO\n", .{});
    }
    pub fn conformParser(flatc: *Compiler, options: Options) !Parser {
        var conform_parser = Parser.init(flatc.allocator, options.opts);
        // flatbuffers::Parser conform_parser;
        // if (!options.conform_to_schema.empty()) {
        //   std::string contents;
        //   if (!flatbuffers::LoadFile(options.conform_to_schema.c_str(), true,
        //                              &contents)) {
        //     Error("unable to load schema: " + options.conform_to_schema);
        //   }

        //   if (flatbuffers::GetExtension(options.conform_to_schema) ==
        //       reflection::SchemaExtension()) {
        //     LoadBinarySchema(conform_parser, options.conform_to_schema, contents);
        //   } else {
        //     ParseFile(conform_parser, options.conform_to_schema, contents,
        //               options.conform_include_directories);
        //   }
        // }
        return conform_parser;
    }

    pub fn registerCodeGenerator(flatc: *Compiler, option: Option, cg: *CodeGenerator) !void {
        {
            var gop = try flatc.getOrPutCodeGenerator("-", option.short_opt);
            if (option.short_opt.len != 0 and gop.found_existing) {
                _err(
                    flatc,
                    "multiple generators registered under: -{s}",
                    .{option.short_opt},
                    ErrOpts.init(false, false),
                );
            }

            if (option.short_opt.len != 0) {
                // code_generators_["-" + option.short_opt] = code_generator;
                gop.value_ptr.* = cg;
            }
        }

        // if (option.long_opt.len != 0 and
        //     code_generators_.find("--" + option.long_opt) != code_generators_.end())
        // {
        //     Error("multiple generators registered under: --" + option.long_opt, false, false);
        //     return false;
        // }
        {
            var gop = try flatc.getOrPutCodeGenerator("-", option.long_opt);
            if (option.long_opt.len != 0 and gop.found_existing) {
                _err(
                    flatc,
                    "multiple generators registered under: --{s}",
                    .{option.long_opt},
                    ErrOpts.init(false, false),
                );
            }

            if (option.long_opt.len != 0) {
                // code_generators_["-" + option.short_opt] = code_generator;
                gop.value_ptr.* = cg;
            }
        }
        //   if (!option.long_opt.empty()) {
        //     code_generators_["--" + option.long_opt] = code_generator;
        //   }

        try language_options.put(flatc.allocator, option, {});
    }
    pub fn compile(flatc: *Compiler, options: Options) !void {
        var conform_parser = try flatc.conformParser(options);
        // if (!options.annotate_schema.empty()) {
        //   const std::string ext = flatbuffers::GetExtension(options.annotate_schema);
        //   if (!(ext == reflection::SchemaExtension() || ext == "fbs")) {
        //     Error("Expected a `.bfbs` or `.fbs` schema, got: " +
        //           options.annotate_schema);
        //   }

        //   const bool is_binary_schema = ext == reflection::SchemaExtension();

        //   std::string schema_contents;
        //   if (!flatbuffers::LoadFile(options.annotate_schema.c_str(),
        //                              /*binary=*/is_binary_schema, &schema_contents)) {
        //     Error("unable to load schema: " + options.annotate_schema);
        //   }

        //   const uint8_t *binary_schema = nullptr;
        //   uint64_t binary_schema_size = 0;

        //   IDLOptions binary_opts;
        //   binary_opts.lang_to_generate |= flatbuffers::IDLOptions::kBinary;
        //   Parser parser(binary_opts);

        //   if (is_binary_schema) {
        //     binary_schema =
        //         reinterpret_cast<const uint8_t *>(schema_contents.c_str());
        //     binary_schema_size = schema_contents.size();
        //   } else {
        //     // If we need to generate the .bfbs file from the provided schema file
        //     // (.fbs)
        //     ParseFile(parser, options.annotate_schema, schema_contents,
        //               options.include_directories);
        //     parser.Serialize();

        //     binary_schema = parser.builder_.GetBufferPointer();
        //     binary_schema_size = parser.builder_.GetSize();
        //   }

        //   if (binary_schema == nullptr || !binary_schema_size) {
        //     Error("could not parse a value binary schema from: " +
        //           options.annotate_schema);
        //   }

        //   // Annotate the provided files with the binary_schema.
        //   AnnotateBinaries(binary_schema, binary_schema_size, options);

        //   // We don't support doing anything else after annotating a binary.
        //   return 0;
        // }

        if (options.generators.items.len == 0) {
            err(flatc, "No generator registered", .{});
            return error.NoGenerators;
        }

        const parser = try generateCode(flatc, options, conform_parser);

        for (options.generators.items) |generator| {
            if (generator.supportsRootFileGeneration(generator))
                try generator.generateRootFile(generator, parser, options.output_path);
        }
    }
};

pub const Option = struct {
    short_opt: []const u8,
    long_opt: []const u8,
    parameter: []const u8,
    description: []const u8,

    pub fn init(
        short_opt: []const u8,
        long_opt: []const u8,
        parameter: []const u8,
        description: []const u8,
    ) Option {
        return .{
            .short_opt = short_opt,
            .long_opt = long_opt,
            .parameter = parameter,
            .description = description,
        };
    }
};

pub const Options = struct {
    opts: idl.Options,
    program_name: []const u8 = "",
    output_path: []const u8 = "",
    filenames: StringList = .{},
    include_directories_storage: StringList = .{},
    include_directories: StringList = .{},
    conform_include_directories: StringList = .{},
    generator_enabled: std.ArrayListUnmanaged(bool) = .{},
    binary_files_from: usize = std.math.maxInt(usize),
    conform_to_schema: []const u8 = "",
    annotate_schema: []const u8 = "",
    annotate_include_vector_contents: bool = true,
    any_generator: bool = false,
    print_make_rules: bool = false,
    raw_binary: bool = false,
    schema_binary: bool = false,
    grpc_enabled: bool = false,
    requires_bfbs: bool = false,
    generators: std.ArrayListUnmanaged(*CodeGenerator) = .{},
};

fn getExtension(
    filename: []const u8,
) []const u8 {
    const idx = if (mem.lastIndexOfScalar(u8, filename, '.')) |i| i + 1 else 0;
    return filename[idx..];
}

fn parseFile(
    flatc: *const Compiler,
    parser: *Parser,
    filename: []const u8,
    contents: []const u8,
    include_directories: []const []const u8,
) !void {
    _ = .{ flatc, parser, filename, contents, include_directories };
    const alloc = flatc.allocator;
    const local_include_directory = stripFileName(filename);
    var inc_directories = std.ArrayListUnmanaged([]const u8){};
    defer inc_directories.deinit(alloc);
    try inc_directories.appendSlice(alloc, include_directories);
    try inc_directories.append(alloc, local_include_directory);
    parser.parse(contents, inc_directories.items, filename) catch {
        err(flatc, "{s}", .{parser.error_.items});
    };
    if (parser.error_.items.len != 0) {
        warn(flatc, "{s}", .{parser.error_.items}, .{});
    }
}

fn generateCode(
    flatc: *const Compiler,
    options: Options,
    conform_parser: Parser,
) !Parser {
    _ = conform_parser;
    var parser = try Parser.create(flatc.allocator, options.opts);

    for (options.filenames.items) |filename| {
        const contents = util.loadFile(flatc.allocator, filename) catch {
            err(flatc, "unable to load file '{s}'", .{filename});
        };
        var opts = options.opts;
        const ext = getExtension(filename);
        const is_binary = false;
        const is_schema = mem.eql(u8, ext, "fbs");
        if (is_schema and opts.project_root.len == 0)
            opts.project_root = stripFileName(filename);

        const is_binary_schema = mem.eql(u8, ext, "bfbs");

        if (is_binary) {
            todo("is_binary", .{});
        } else {
            // if (!opts.use_flexbuffers && !is_binary_schema &&
            //   contents.length() != strlen(contents.c_str())) {
            // Error("input file appears to be binary: " + filename, true);
            // }
            if (is_schema or is_binary_schema) {
                // If we're processing multiple schemas, make sure to start each
                // one from scratch. If it depends on previous schemas it must do
                // so explicitly using an include.
                parser = try Parser.create(flatc.allocator, opts);
            }
            if (is_binary_schema) {
                todo("is_binary_schema", .{});
            } else if (opts.use_flexbuffers) {
                todo("use_flexbuffers", .{});
            } else {
                try parseFile(flatc, &parser, filename, contents, options.include_directories.items);
                if (!is_schema and parser.builder_.buf_.items.len == 0) {
                    // If a file doesn't end in .fbs, it must be json/binary. Ensure we
                    // didn't just parse a schema with a different extension.
                    errWithUsage(flatc, "input file is neither json nor a .fbs (schema) file: {s}", .{filename});
                }
            }

            // if ((is_schema || is_binary_schema) &&
            //     !options.conform_to_schema.empty()) {
            //   auto err = parser->ConformTo(conform_parser);
            //   if (!err.empty()) Error("schemas don\'t conform: " + err, false);
            // }
            // if (options.schema_binary || opts.binary_schema_gen_embed) {
            //   parser->Serialize();
            // }
            // if (options.schema_binary) {
            //   parser->file_extension_ = reflection::SchemaExtension();
            // }
        }
    }

    //   std::string filebase =
    //       flatbuffers::StripPath(flatbuffers::StripExtension(filename));

    //   // If one of the generators uses bfbs, serialize the parser and get
    //   // the serialized buffer and length.
    //   const uint8_t *bfbs_buffer = nullptr;
    //   int64_t bfbs_length = 0;
    //   if (options.requires_bfbs) {
    //     parser->Serialize();
    //     bfbs_buffer = parser->builder_.GetBufferPointer();
    //     bfbs_length = parser->builder_.GetSize();
    //   }

    //   for (const std::shared_ptr<CodeGenerator> &code_generator :
    //        options.generators) {
    //     if (options.print_make_rules) {
    //       std::string make_rule;
    //       const CodeGenerator::Status status = code_generator->GenerateMakeRule(
    //           *parser, options.output_path, filename, make_rule);
    //       if (status == CodeGenerator::Status::OK && !make_rule.empty()) {
    //         printf("%s\n",
    //                flatbuffers::WordWrap(make_rule, 80, " ", " \\").c_str());
    //       } else {
    //         Error("Cannot generate make rule for " +
    //               code_generator->LanguageName());
    //       }
    //     } else {
    //       flatbuffers::EnsureDirExists(options.output_path);

    //       // Prefer bfbs generators if present.
    //       if (code_generator->SupportsBfbsGeneration()) {
    //         const CodeGenerator::Status status =
    //             code_generator->GenerateCode(bfbs_buffer, bfbs_length);
    //         if (status != CodeGenerator::Status::OK) {
    //           Error("Unable to generate " + code_generator->LanguageName() +
    //                 " for " + filebase + " using bfbs generator.");
    //         }
    //       } else {
    //         if ((!code_generator->IsSchemaOnly() ||
    //              (is_schema || is_binary_schema)) &&
    //             code_generator->GenerateCode(*parser, options.output_path,
    //                                          filebase) !=
    //                 CodeGenerator::Status::OK) {
    //           Error("Unable to generate " + code_generator->LanguageName() +
    //                 " for " + filebase);
    //         }
    //       }
    //     }

    //     if (options.grpc_enabled) {
    //       const CodeGenerator::Status status = code_generator->GenerateGrpcCode(
    //           *parser, options.output_path, filebase);

    //       if (status == CodeGenerator::Status::NOT_IMPLEMENTED) {
    //         Warn("GRPC interface generator not implemented for " +
    //              code_generator->LanguageName());
    //       } else if (status == CodeGenerator::Status::ERROR) {
    //         Error("Unable to generate GRPC interface for " +
    //               code_generator->LanguageName());
    //       }
    //     }
    //   }

    //   if (!opts.root_type.empty()) {
    //     if (!parser->SetRootType(opts.root_type.c_str()))
    //       Error("unknown root type: " + opts.root_type);
    //     else if (parser->root_struct_def_->fixed)
    //       Error("root type must be a table");
    //   }

    //   if (opts.proto_mode) GenerateFBS(*parser, options.output_path, filebase);

    //   // We do not want to generate code for the definitions in this file
    //   // in any files coming up next.
    //   parser->MarkGenerated();
    // }

    return parser;
}
