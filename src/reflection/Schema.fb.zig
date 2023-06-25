//!
//! generated by flatc-zig
//! binary:     gen/home/travis/Downloads/flatbuffers/reflection/reflection.bfbs
//! schema:     /home/travis/Downloads/flatbuffers/reflection/reflection.fbs
//! file ident: //reflection.fbs
//! typename    reflection.Schema
//!

const std = @import("std");
const fb = @import("flatbufferz");
const Builder = fb.Builder;

// a namespace generated by flatc-zig to match typenames produced by flatc
const reflection = struct {
    const SchemaFile = @import("SchemaFile.fb.zig").SchemaFile;
    const SchemaFileT = @import("SchemaFile.fb.zig").SchemaFileT;
    const Object = @import("Object.fb.zig").Object;
    const ObjectT = @import("Object.fb.zig").ObjectT;
    const Schema = @import("Schema.fb.zig").Schema;
    const SchemaT = @import("Schema.fb.zig").SchemaT;
    const AdvancedFeatures = @import("AdvancedFeatures.fb.zig").AdvancedFeatures;
    const Enum = @import("Enum.fb.zig").Enum;
    const EnumT = @import("Enum.fb.zig").EnumT;
    const Service = @import("Service.fb.zig").Service;
    const ServiceT = @import("Service.fb.zig").ServiceT;
};

pub const Schema = struct {
    _tab: fb.Table,

    pub fn GetRootAs(buf: []u8, offset: u32) reflection.Schema {
        const n = fb.encode.read(u32, buf[offset..]);
        return reflection.Schema.init(buf, n + offset);
    }

    pub fn GetSizePrefixedRootAs(buf: []u8, offset: u32) reflection.Schema {
        const n = fb.encode.read(u32, buf[offset + fb.Builder.size_u32 ..]);
        return reflection.Schema.init(buf, n + offset + fb.Builder.size_u32);
    }

    pub fn init(bytes: []u8, pos: u32) Schema {
        return .{ ._tab = .{ .bytes = bytes, .pos = pos } };
    }

    pub fn Table(x: Schema) fb.Table {
        return x._tab;
    }

    pub fn Objects(rcv: Schema, j: usize) ?reflection.Object {
        const o = rcv._tab.offset(4);
        if (o != 0) {
            var x = rcv._tab.vector(o);
            x += @intCast(u32, j) * 4;
            x = rcv._tab.indirect(x);
            return reflection.Object.init(rcv._tab.bytes, x);
        }
        return null;
    }

    pub fn ObjectsByKey(rcv: Schema, obj: *reflection.Object, key: []const u8) bool {
        const o = rcv._tab.offset(4);
        if (o != 0) {
            const x = rcv._tab.vector(o);
            return obj.LookupByKey(key, x, rcv._tab.bytes);
        }
        return false;
    }

    pub fn ObjectsLen(rcv: Schema) u32 {
        const o = rcv._tab.offset(4);
        if (o != 0) {
            return rcv._tab.vectorLen(o);
        }
        return 0;
    }

    pub fn Enums(rcv: Schema, j: usize) ?reflection.Enum {
        const o = rcv._tab.offset(6);
        if (o != 0) {
            var x = rcv._tab.vector(o);
            x += @intCast(u32, j) * 4;
            x = rcv._tab.indirect(x);
            return reflection.Enum.init(rcv._tab.bytes, x);
        }
        return null;
    }

    pub fn EnumsByKey(rcv: Schema, obj: *reflection.Enum, key: []const u8) bool {
        const o = rcv._tab.offset(6);
        if (o != 0) {
            const x = rcv._tab.vector(o);
            return obj.LookupByKey(key, x, rcv._tab.bytes);
        }
        return false;
    }

    pub fn EnumsLen(rcv: Schema) u32 {
        const o = rcv._tab.offset(6);
        if (o != 0) {
            return rcv._tab.vectorLen(o);
        }
        return 0;
    }

    pub fn FileIdent(rcv: Schema) []const u8 {
        const o = rcv._tab.offset(8);
        if (o != 0) {
            return rcv._tab.byteVector(o + rcv._tab.pos);
        }
        return "";
    }

    pub fn FileExt(rcv: Schema) []const u8 {
        const o = rcv._tab.offset(10);
        if (o != 0) {
            return rcv._tab.byteVector(o + rcv._tab.pos);
        }
        return "";
    }

    pub fn RootTable(rcv: Schema) ?reflection.Object {
        const o = rcv._tab.offset(12);
        if (o != 0) {
            const x = rcv._tab.indirect(o + rcv._tab.pos);
            return reflection.Object.init(rcv._tab.bytes, x);
        }
        return null;
    }

    pub fn Services(rcv: Schema, j: usize) ?reflection.Service {
        const o = rcv._tab.offset(14);
        if (o != 0) {
            var x = rcv._tab.vector(o);
            x += @intCast(u32, j) * 4;
            x = rcv._tab.indirect(x);
            return reflection.Service.init(rcv._tab.bytes, x);
        }
        return null;
    }

    pub fn ServicesByKey(rcv: Schema, obj: *reflection.Service, key: []const u8) bool {
        const o = rcv._tab.offset(14);
        if (o != 0) {
            const x = rcv._tab.vector(o);
            return obj.LookupByKey(key, x, rcv._tab.bytes);
        }
        return false;
    }

    pub fn ServicesLen(rcv: Schema) u32 {
        const o = rcv._tab.offset(14);
        if (o != 0) {
            return rcv._tab.vectorLen(o);
        }
        return 0;
    }

    pub fn AdvancedFeatures(rcv: Schema) reflection.AdvancedFeatures {
        const o = rcv._tab.offset(16);
        if (o != 0) {
            return rcv._tab.read(reflection.AdvancedFeatures, o + rcv._tab.pos);
        }
        return @enumFromInt(reflection.AdvancedFeatures, 0);
    }

    pub fn MutateAdvancedFeatures(rcv: Schema, n: reflection.AdvancedFeatures) bool {
        return rcv._tab.mutateSlot(reflection.AdvancedFeatures, 16, n);
    }

    /// All the files used in this compilation. Files are relative to where
    /// flatc was invoked.
    pub fn FbsFiles(rcv: Schema, j: usize) ?reflection.SchemaFile {
        const o = rcv._tab.offset(18);
        if (o != 0) {
            var x = rcv._tab.vector(o);
            x += @intCast(u32, j) * 4;
            x = rcv._tab.indirect(x);
            return reflection.SchemaFile.init(rcv._tab.bytes, x);
        }
        return null;
    }

    pub fn FbsFilesByKey(rcv: Schema, obj: *reflection.SchemaFile, key: []const u8) bool {
        const o = rcv._tab.offset(18);
        if (o != 0) {
            const x = rcv._tab.vector(o);
            return obj.LookupByKey(key, x, rcv._tab.bytes);
        }
        return false;
    }

    pub fn FbsFilesLen(rcv: Schema) u32 {
        const o = rcv._tab.offset(18);
        if (o != 0) {
            return rcv._tab.vectorLen(o);
        }
        return 0;
    }

    pub fn Start(__builder: *Builder) !void {
        try __builder.startObject(8);
    }
    pub fn AddObjects(__builder: *Builder, objects: u32) !void {
        try __builder.prependSlotUOff(0, objects, 0);
    }

    pub fn StartObjectsVector(__builder: *Builder, num_elems: i32) !u32 {
        return __builder.startVector(4, num_elems, 1);
    }
    pub fn AddEnums(__builder: *Builder, enums: u32) !void {
        try __builder.prependSlotUOff(1, enums, 0);
    }

    pub fn StartEnumsVector(__builder: *Builder, num_elems: i32) !u32 {
        return __builder.startVector(4, num_elems, 1);
    }
    pub fn AddFileIdent(__builder: *Builder, file_ident: u32) !void {
        try __builder.prependSlotUOff(2, file_ident, 0);
    }

    pub fn AddFileExt(__builder: *Builder, file_ext: u32) !void {
        try __builder.prependSlotUOff(3, file_ext, 0);
    }

    pub fn AddRootTable(__builder: *Builder, root_table: u32) !void {
        try __builder.prependSlotUOff(4, root_table, 0);
    }

    pub fn AddServices(__builder: *Builder, services: u32) !void {
        try __builder.prependSlotUOff(5, services, 0);
    }

    pub fn StartServicesVector(__builder: *Builder, num_elems: i32) !u32 {
        return __builder.startVector(4, num_elems, 1);
    }
    pub fn AddAdvancedFeatures(__builder: *Builder, advanced_features: reflection.AdvancedFeatures) !void {
        try __builder.prependSlot(reflection.AdvancedFeatures, 6, advanced_features, @enumFromInt(reflection.AdvancedFeatures, 0));
    }

    pub fn AddFbsFiles(__builder: *Builder, fbs_files: u32) !void {
        try __builder.prependSlotUOff(7, fbs_files, 0);
    }

    pub fn StartFbsFilesVector(__builder: *Builder, num_elems: i32) !u32 {
        return __builder.startVector(4, num_elems, 1);
    }
    pub fn End(__builder: *Builder) !u32 {
        return __builder.endObject();
    }
};
