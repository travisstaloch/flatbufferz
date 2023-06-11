//!
//! a port of https://github.com/google/flatbuffers/blob/master/tests/go_test.go
//!

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const fb = @import("flatbufferz");
const Builder = fb.Builder;
const gen = @import("generated");
const Monster = gen.MyGame_Example_Monster.Monster;
const MonsterT = gen.MyGame_Example_Monster.MonsterT;
const Test = gen.MyGame_Example_Test.Test;
const Vec3 = gen.MyGame_Example_Vec3.Vec3;
const Color = gen.MyGame_Example_Color.Color;
const Any = gen.MyGame_Example_Any.Any;
const Stat = gen.MyGame_Example_Stat.Stat;
const StatT = gen.MyGame_Example_Stat.StatT;
const InParentNamespace = gen.MyGame_InParentNamespace.InParentNamespace;
const PizzaT = gen.Pizza.PizzaT;
const FoodT = gen.order_Food.FoodT;
const Food = gen.order_Food.Food;
const ScalarStuff = gen.optional_scalars_ScalarStuff.ScalarStuff;
const ScalarStuffT = gen.optional_scalars_ScalarStuff.ScalarStuffT;
const OptionalByte = gen.optional_scalars_OptionalByte.OptionalByte;

const expectEqualDeep = @import("testing.zig").expectEqualDeep;

test {
    _ = @import("../examples/sample_binary.zig");
}

// build an example Monster. returns (buf,offset)
fn checkGeneratedBuild(
    alloc: mem.Allocator,
    sizePrefix: bool,
    file_identifier: ?[4]u8,
) !struct { []u8, u32 } {
    var b = Builder.init(alloc);
    defer b.deinit();

    const str = try b.createString("MyMonster");
    const test1 = try b.createString("test1");
    const test2 = try b.createString("test2");
    const fred = try b.createString("Fred");

    _ = try Monster.StartInventoryVector(&b, 5);
    try b.prepend(u8, 4);
    try b.prepend(u8, 3);
    try b.prepend(u8, 2);
    try b.prepend(u8, 1);
    try b.prepend(u8, 0);
    const inv = try b.endVector(5);

    try Monster.Start(&b);
    try Monster.AddName(&b, fred);
    const mon2 = try Monster.End(&b);

    _ = try Monster.StartTest4Vector(&b, 2);
    _ = try Test.Create(&b, 10, 20);
    _ = try Test.Create(&b, 30, 40);
    const test4 = try b.endVector(2);

    _ = try Monster.StartTestarrayofstringVector(&b, 2);
    try b.prependUOff(test2);
    try b.prependUOff(test1);
    const testArrayOfString = try b.endVector(2);

    try Monster.Start(&b);

    const pos = try Vec3.Create(&b, 1.0, 2.0, 3.0, 3.0, .Green, 5, 6);
    try Monster.AddPos(&b, pos);

    try Monster.AddHp(&b, 80);
    try Monster.AddName(&b, str);
    try Monster.AddTestbool(&b, true);
    try Monster.AddInventory(&b, inv);
    try Monster.AddTestType(&b, .Monster);
    try Monster.AddTest(&b, mon2);
    try Monster.AddTest4(&b, test4);
    try Monster.AddTestarrayofstring(&b, testArrayOfString);
    const mon = try Monster.End(&b);

    if (sizePrefix) {
        if (file_identifier) |fid|
            try b.finishSizePrefixedWithFileIdentifier(mon, fid)
        else
            try b.finishSizePrefixed(mon);
    } else {
        if (file_identifier) |fid|
            try b.finishWithFileIdentifier(mon, fid)
        else
            try b.finish(mon);
    }

    return .{ try b.bytes.toOwnedSlice(b.alloc), b.head };
}

fn check(want: []const u8, b: Builder, i: *usize) !void {
    i.* += 1;
    const got = b.bytes.items[b.head..];
    try testing.expectEqualStrings(want, got);
}

/// verify the bytes of a Builder in various scenarios.
fn checkByteLayout(alloc: mem.Allocator) !void {
    var i: usize = 0;
    { // test 1: numbers
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try check(&[_]u8{}, b, &i);
        try b.prepend(bool, true);
        try check(&[_]u8{1}, b, &i);
        try b.prepend(i8, -127);
        try check(&[_]u8{ 129, 1 }, b, &i);
        try b.prepend(u8, 255);
        try check(&[_]u8{ 255, 129, 1 }, b, &i);
        try b.prepend(i16, -32222);
        try check(&[_]u8{ 0x22, 0x82, 0, 255, 129, 1 }, b, &i); // first pa
        try b.prepend(u16, 0xFEEE);
        try check(&[_]u8{ 0xEE, 0xFE, 0x22, 0x82, 0, 255, 129, 1 }, b, &i); // no pad this tim
        try b.prepend(i32, -53687092);
        try check(&[_]u8{ 204, 204, 204, 252, 0xEE, 0xFE, 0x22, 0x82, 0, 255, 129, 1 }, b, &i);
        try b.prepend(u32, 0x98765432);
        try check(&[_]u8{ 0x32, 0x54, 0x76, 0x98, 204, 204, 204, 252, 0xEE, 0xFE, 0x22, 0x82, 0, 255, 129, 1 }, b, &i);
    }
    { // test 1b: numbers 2
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try b.prepend(u64, 0x1122334455667788);
        try check(&[_]u8{ 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11 }, b, &i);
    }
    { // test 2: 1xbyte vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try check(&[_]u8{}, b, &i);
        _ = try b.startVector(fb.Builder.size_byte, 1, 1);
        try check(&[_]u8{ 0, 0, 0 }, b, &i); // align to 4byte
        try b.prepend(u8, 1);
        try check(&[_]u8{ 1, 0, 0, 0 }, b, &i);
        _ = try b.endVector(1);
        try check(&[_]u8{ 1, 0, 0, 0, 1, 0, 0, 0 }, b, &i); // paddin
    }
    { // test 3: 2xbyte vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_byte, 2, 1);
        try check(&[_]u8{ 0, 0 }, b, &i); // align to 4byte
        try b.prepend(u8, 1);
        try check(&[_]u8{ 1, 0, 0 }, b, &i);
        try b.prepend(u8, 2);
        try check(&[_]u8{ 2, 1, 0, 0 }, b, &i);
        _ = try b.endVector(2);
        try check(&[_]u8{ 2, 0, 0, 0, 2, 1, 0, 0 }, b, &i); // paddin
    }
    { // test 3b: 11xbyte vector matches builder size
        var b = try Builder.initCapacity(alloc, 12);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_byte, 8, 1);
        var start = std.ArrayList(u8).init(alloc);
        defer start.deinit();
        try check(start.items, b, &i);
        for (1..12) |j| {
            try b.prepend(u8, @intCast(u8, j));
            try start.insert(0, @intCast(u8, j));
            try check(start.items, b, &i);
        }
        _ = try b.endVector(8);
        try start.insertSlice(0, &.{ 8, 0, 0, 0 });
        try check(start.items, b, &i);
    }

    { // test 4: 1xu16 vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_u16, 1, 1);
        try check(&[_]u8{ 0, 0 }, b, &i); // align to 4byte
        try b.prepend(u16, 1);
        try check(&[_]u8{ 1, 0, 0, 0 }, b, &i);
        _ = try b.endVector(1);
        try check(&[_]u8{ 1, 0, 0, 0, 1, 0, 0, 0 }, b, &i); // paddin
    }

    { // test 5: 2xu16 vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_u16, 2, 1);
        try check(&[_]u8{}, b, &i); // align to 4byte
        try b.prepend(u16, 0xABCD);
        try check(&[_]u8{ 0xCD, 0xAB }, b, &i);
        try b.prepend(u16, 0xDCBA);
        try check(&[_]u8{ 0xBA, 0xDC, 0xCD, 0xAB }, b, &i);
        _ = try b.endVector(2);
        try check(&[_]u8{ 2, 0, 0, 0, 0xBA, 0xDC, 0xCD, 0xAB }, b, &i);
    }

    { // test 6: CreateString
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.createString("foo");
        try check(&[_]u8{ 3, 0, 0, 0, 'f', 'o', 'o', 0 }, b, &i); // 0-terminated, no pa
        _ = try b.createString("moop");
        try check(&[_]u8{
            4, 0, 0, 0, 'm', 'o', 'o', 'p', 0, 0, 0, 0, // 0-terminated, 3-byte pa
            3, 0, 0, 0, 'f', 'o', 'o', 0,
        }, b, &i);
    }

    { // test 6b: CreateString unicode
        var b = Builder.init(alloc);
        defer b.deinitAll();

        // These characters are chinese from blog.golang.org/strings
        // We use escape codes here so that editors without unicode support
        // aren't bothered:
        const uni_str = "\u{65e5}\u{672c}\u{8a9e}";
        _ = try b.createString(uni_str);
        try check(&[_]u8{
            9, 0, 0, 0, 230, 151, 165, 230, 156, 172, 232, 170, 158, 0, //  null-terminated, 2-byte pa
            0, 0,
        }, b, &i);
    }

    { // test 6c: CreateByteString
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.createByteString("foo");
        try check(&[_]u8{ 3, 0, 0, 0, 'f', 'o', 'o', 0 }, b, &i); // 0-terminated, no pa
        _ = try b.createByteString("moop");
        try check(&[_]u8{
            4, 0, 0, 0, 'm', 'o', 'o', 'p', 0, 0, 0, 0, // 0-terminated, 3-byte pa
            3, 0, 0, 0, 'f', 'o', 'o', 0,
        }, b, &i);
    }
    { // test 7: empty vtable
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try b.startObject(0);
        try check(&[_]u8{}, b, &i);
        _ = try b.endObject();
        try check(&[_]u8{ 4, 0, 4, 0, 4, 0, 0, 0 }, b, &i);
    }
    { // test 8: vtable with one true bool
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try check(&[_]u8{}, b, &i);
        try b.startObject(1);
        try check(&[_]u8{}, b, &i);
        try b.prependSlot(bool, 0, true, false);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0, // length of object including vtable offset
            7, 0, // start of bool value
            6, 0, 0, 0, // offset for start of vtable (i32)
            0, 0, 0, // padded to 4 bytes
            1, // bool value
        }, b, &i);
    }
    { // test 9: vtable with one default bool
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try check(&[_]u8{}, b, &i);
        try b.startObject(1);
        try check(&[_]u8{}, b, &i);
        try b.prependSlot(bool, 0, false, false);
        _ = try b.endObject();
        try check(&[_]u8{
            4, 0, // vtable bytes
            4, 0, // end of object from here
            // entry 1 is zero and not stored.
            4, 0, 0, 0, // offset for start of vtable (i32)
        }, b, &i);
    }
    { // test 10: vtable with one i16
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try b.startObject(1);
        try b.prependSlot(i16, 0, 0x789A, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0, // end of object from here
            6, 0, // offset to value
            6, 0, 0, 0, // offset for start of vtable (i32)
            0,    0, // padding to 4 bytes
            0x9A, 0x78,
        }, b, &i);
    }
    { // test 11: vtable with two i16
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try b.startObject(2);
        try b.prependSlot(i16, 0, 0x3456, 0);
        try b.prependSlot(i16, 1, 0x789A, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            8, 0, // vtable bytes
            8, 0, // end of object from here
            6, 0, // offset to value 0
            4, 0, // offset to value 1
            8, 0, 0, 0, // offset for start of vtable (i32)
            0x9A, 0x78, // value 1
            0x56, 0x34, // value 0
        }, b, &i);
    }
    { // test 12: vtable with i16 and bool
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try b.startObject(2);
        try b.prependSlot(i16, 0, 0x3456, 0);
        try b.prependSlot(bool, 1, true, false);
        _ = try b.endObject();
        try check(&[_]u8{
            8, 0, // vtable bytes
            8, 0, // end of object from here
            6, 0, // offset to value 0
            5, 0, // offset to value 1
            8, 0, 0, 0, // offset for start of vtable (i32)
            0, // padding
            1, // value 1
            0x56, 0x34, // value 0
        }, b, &i);
    }
    { // test 12: vtable with empty vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_byte, 0, 1);
        const vecend = try b.endVector(0);
        _ = try b.startObject(1);
        try b.prependSlotUOff(0, vecend, 0);

        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0,
            4, 0, // offset to vector offset
            6, 0, 0, 0, // offset for start of vtable (i32)
            4, 0, 0, 0,
            0, 0, 0, 0, // length of vector (not in struct)
        }, b, &i);
    }
    { // test 12b: vtable with empty vector of byte and some scalars
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_byte, 0, 1);
        const vecend = try b.endVector(0);
        _ = try b.startObject(2);
        try b.prependSlot(i16, 0, 55, 0);
        try b.prependSlotUOff(1, vecend, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            8,  0, // vtable bytes
            12, 0,
            10, 0, // offset to value 0
            4, 0, // offset to vector offset
            8, 0, 0, 0, // vtable loc
            8, 0, 0, 0, // value 1
            0, 0, 55, 0, // value 0
            0, 0, 0, 0, // length of vector (not in struct)
        }, b, &i);
    }
    { // test 13: vtable with 1 i16 and 2-vector of i16
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_i16, 2, 1);
        try b.prepend(i16, 0x1234);
        try b.prepend(i16, 0x5678);
        const vecend = try b.endVector(2);
        _ = try b.startObject(2);
        try b.prependSlotUOff(1, vecend, 0);
        try b.prependSlot(i16, 0, 55, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            8, 0, // vtable bytes
            12, 0, // length of object
            6, 0, // start of value 0 from end of vtable
            8, 0, // start of value 1 from end of buffer
            8, 0, 0, 0, // offset for start of vtable (i32)
            0, 0, // padding
            55, 0, // value 0
            4, 0, 0, 0, // vector position from here
            2, 0, 0, 0, // length of vector (u32)
            0x78, 0x56, // vector value 1
            0x34, 0x12, // vector value 0
        }, b, &i);
    }
    { // test 14: vtable with 1 struct of 1 i8, 1 i16, 1 i32
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startObject(1);
        try b.prep(4 + 4 + 4, 0);
        try b.prepend(i8, 55);
        b.pad(3);
        try b.prepend(i16, 0x1234);
        b.pad(2);
        try b.prepend(i32, 0x12345678);
        const structStart = b.offset();
        try b.prependSlotStruct(0, structStart, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            16, 0, // end of object from here
            4, 0, // start of struct from here
            6, 0, 0, 0, // offset for start of vtable (i32)
            0x78, 0x56, 0x34, 0x12, // value 2
            0, 0, // padding
            0x34, 0x12, // value 1
            0, 0, 0, // padding
            55, // value 0
        }, b, &i);
    }
    { // test 15: vtable with 1 vector of 2 struct of 2 i8
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_i8 * 2, 2, 1);
        try b.prepend(i8, 33);
        try b.prepend(i8, 44);
        try b.prepend(i8, 55);
        try b.prepend(i8, 66);
        const vecend = try b.endVector(2);
        _ = try b.startObject(1);
        try b.prependSlotUOff(0, vecend, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0,
            4, 0, // offset of vector offset
            6, 0, 0, 0, // offset for start of vtable (i32)
            4, 0, 0, 0, // vector start offset
            2, 0, 0, 0, // vector length
            66, // vector value 1,1
            55, // vector value 1,0
            44, // vector value 0,1
            33, // vector value 0,0
        }, b, &i);
    }
    { // test 16: table with some elements
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startObject(2);
        try b.prependSlot(i8, 0, 33, 0);
        try b.prependSlot(i16, 1, 66, 0);
        const off = try b.endObject();
        try b.finish(off);

        try check(&[_]u8{
            12, 0, 0, 0, // root of table: points to vtable offset
            8, 0, // vtable bytes
            8, 0, // end of object from here
            7, 0, // start of value 0
            4, 0, // start of value 1
            8, 0, 0, 0, // offset for start of vtable (i32)
            66, 0, // value 1
            0, // padding
            33, // value 0
        }, b, &i);
    }
    { // test 17: one unfinished table and one finished table
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startObject(2);
        try b.prependSlot(i8, 0, 33, 0);
        try b.prependSlot(i8, 1, 44, 0);
        var off = try b.endObject();
        try b.finish(off);

        _ = try b.startObject(3);
        try b.prependSlot(i8, 0, 55, 0);
        try b.prependSlot(i8, 1, 66, 0);
        try b.prependSlot(i8, 2, 77, 0);
        off = try b.endObject();
        try b.finish(off);

        try check(&[_]u8{
            16, 0, 0, 0, // root of table: points to object
            0, 0, // padding
            10, 0, // vtable bytes
            8, 0, // size of object
            7, 0, // start of value 0
            6, 0, // start of value 1
            5, 0, // start of value 2
            10, 0, 0, 0, // offset for start of vtable (i32)
            0, // padding
            77, // value 2
            66, // value 1
            55, // value 0
            12, 0, 0, 0, // root of table: points to object
            8, 0, // vtable bytes
            8, 0, // size of object
            7, 0, // start of value 0
            6, 0, // start of value 1
            8, 0, 0, 0, // offset for start of vtable (i32)
            0, 0, // padding
            44, // value 1
            33, // value 0
        }, b, &i);
    }
    { // test 18: a bunch of bools
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startObject(8);
        try b.prependSlot(bool, 0, true, false);
        try b.prependSlot(bool, 1, true, false);
        try b.prependSlot(bool, 2, true, false);
        try b.prependSlot(bool, 3, true, false);
        try b.prependSlot(bool, 4, true, false);
        try b.prependSlot(bool, 5, true, false);
        try b.prependSlot(bool, 6, true, false);
        try b.prependSlot(bool, 7, true, false);
        const off = try b.endObject();
        try b.finish(off);

        try check(&[_]u8{
            24, 0, 0, 0, // root of table: points to vtable offset
            20, 0, // vtable bytes
            12, 0, // size of object
            11, 0, // start of value 0
            10, 0, // start of value 1
            9, 0, // start of value 2
            8, 0, // start of value 3
            7, 0, // start of value 4
            6, 0, // start of value 5
            5, 0, // start of value 6
            4, 0, // start of value 7
            20, 0, 0, 0, // vtable offset
            1, // value 7
            1, // value 6
            1, // value 5
            1, // value 4
            1, // value 3
            1, // value 2
            1, // value 1
            1, // value 0
        }, b, &i);
    }
    { // test 19: three bools
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startObject(3);
        try b.prependSlot(bool, 0, true, false);
        try b.prependSlot(bool, 1, true, false);
        try b.prependSlot(bool, 2, true, false);
        const off = try b.endObject();
        try b.finish(off);

        try check(&[_]u8{
            16, 0, 0, 0, // root of table: points to vtable offset
            0, 0, // padding
            10, 0, // vtable bytes
            8, 0, // size of object
            7, 0, // start of value 0
            6, 0, // start of value 1
            5, 0, // start of value 2
            10, 0, 0, 0, // vtable offset from here
            0, // padding
            1, // value 2
            1, // value 1
            1, // value 0
        }, b, &i);
    }

    { // test 20: some floats
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startObject(1);
        try b.prependSlot(f32, 0, 1.0, 0.0);
        _ = try b.endObject();

        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0, // size of object
            4, 0, // start of value 0
            6, 0, 0, 0, // vtable offset
            0, 0, 128, 63, // value 0
        }, b, &i);
    }
}

fn calcVOffsetT(slot: u16) u16 {
    return (fb.encode.vtable_metadata_fields + slot) * fb.Builder.size_u16;
}

fn calcUOffsetT(vtableOffset: u16, t: fb.Table) u16 {
    return @intCast(u16, t.pos) + t.offset(vtableOffset);
}

/// check all mutate methods one by one
fn checkMutateMethods(alloc: mem.Allocator) !void {
    var b = Builder.init(alloc);
    defer b.deinitAll();

    try b.startObject(15);
    try b.prependSlot(bool, 0, true, false);
    try b.prependSlot(u8, 1, 1, 0);
    try b.prependSlot(u8, 2, 2, 0);
    try b.prependSlot(u16, 3, 3, 0);
    try b.prependSlot(u32, 4, 4, 0);
    try b.prependSlot(u64, 5, 5, 0);
    try b.prependSlot(i8, 6, 6, 0);
    try b.prependSlot(i16, 7, 7, 0);
    try b.prependSlot(i32, 8, 8, 0);
    try b.prependSlot(i64, 9, 9, 0);
    try b.prependSlot(f32, 10, 10, 0);
    try b.prependSlot(f64, 11, 11, 0);

    try b.prependSlotUOff(12, 12, 0);
    const uoVal = b.offset() - 12;

    try b.prepend(u16, 13);
    b.slot(13);

    try b.prependSOff(14);
    b.slot(14);
    const soVal = @intCast(i32, b.offset() - 14);

    const offset = try b.endObject();

    var t = fb.Table{
        .bytes = b.bytes.items,
        .pos = @intCast(u32, b.bytes.items.len) - offset,
    };

    const testForOriginalValues = struct {
        fn func(tb: fb.Table, uoVal_: u32, soVal_: i32) !void {
            try testing.expect(tb.getSlot(bool, calcVOffsetT(0), true));
            try testing.expectEqual(@as(u8, 1), tb.getSlot(u8, calcVOffsetT(1), 1));
            try testing.expectEqual(@as(u8, 2), tb.getSlot(u8, calcVOffsetT(2), 2));
            try testing.expectEqual(@as(u16, 3), tb.getSlot(u16, calcVOffsetT(3), 3));
            try testing.expectEqual(@as(u32, 4), tb.getSlot(u32, calcVOffsetT(4), 4));
            try testing.expectEqual(@as(u64, 5), tb.getSlot(u64, calcVOffsetT(5), 5));

            try testing.expectEqual(@as(i8, 6), tb.getSlot(i8, calcVOffsetT(6), 6));
            try testing.expectEqual(@as(i16, 7), tb.getSlot(i16, calcVOffsetT(7), 7));
            try testing.expectEqual(@as(i32, 8), tb.getSlot(i32, calcVOffsetT(8), 8));
            try testing.expectEqual(@as(i64, 9), tb.getSlot(i64, calcVOffsetT(9), 9));

            try testing.expectEqual(@as(f32, 10), tb.getSlot(f32, calcVOffsetT(10), 10));
            try testing.expectEqual(@as(f64, 11), tb.getSlot(f64, calcVOffsetT(11), 11));

            try testing.expectEqual(uoVal_, tb.read(u32, calcUOffsetT(calcVOffsetT(12), tb)));
            try testing.expectEqual(@as(u16, 13), tb.read(u16, calcUOffsetT(calcVOffsetT(13), tb)));
            try testing.expectEqual(soVal_, tb.read(i32, calcUOffsetT(calcVOffsetT(14), tb)));
        }
    }.func;

    const testMutability = struct {
        fn func(tb: fb.Table) !void {
            try testing.expect(tb.mutateSlot(bool, calcVOffsetT(0), false));
            try testing.expect(tb.mutateSlot(u8, calcVOffsetT(1), 2));
            try testing.expect(tb.mutateSlot(u8, calcVOffsetT(2), 4));
            try testing.expect(tb.mutateSlot(u16, calcVOffsetT(3), 6));
            try testing.expect(tb.mutateSlot(u32, calcVOffsetT(4), 8));
            try testing.expect(tb.mutateSlot(u64, calcVOffsetT(5), 10));
            try testing.expect(tb.mutateSlot(i8, calcVOffsetT(6), 12));
            try testing.expect(tb.mutateSlot(i16, calcVOffsetT(7), 14));
            try testing.expect(tb.mutateSlot(i32, calcVOffsetT(8), 16));
            try testing.expect(tb.mutateSlot(i64, calcVOffsetT(9), 18));
            try testing.expect(tb.mutateSlot(f32, calcVOffsetT(10), 20));
            try testing.expect(tb.mutateSlot(f64, calcVOffsetT(11), 22));
            tb.mutate(u32, calcUOffsetT(calcVOffsetT(12), tb), 24);
            tb.mutate(u16, calcUOffsetT(calcVOffsetT(13), tb), 26);
            tb.mutate(i32, calcUOffsetT(calcVOffsetT(14), tb), 28);
        }
    }.func;

    const testMutabilityWithoutSlot = struct {
        fn func(tb: fb.Table) !void {
            try testing.expect(!tb.mutateSlot(bool, calcVOffsetT(16), false));
            try testing.expect(!tb.mutateSlot(u8, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(u8, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(u16, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(u32, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(u64, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(i8, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(i16, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(i32, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(i64, calcVOffsetT(16), 2));
            try testing.expect(!tb.mutateSlot(f32, calcVOffsetT(160), 2));
            try testing.expect(!tb.mutateSlot(f64, calcVOffsetT(161), 2));
        }
    }.func;

    const testForMutatedValues = struct {
        fn func(tb: fb.Table) !void {
            try testing.expect(!tb.getSlot(bool, calcVOffsetT(0), false));
            try testing.expectEqual(@as(u8, 2), tb.getSlot(u8, calcVOffsetT(1), 1));
            try testing.expectEqual(@as(u8, 4), tb.getSlot(u8, calcVOffsetT(2), 1));
            try testing.expectEqual(@as(u16, 6), tb.getSlot(u16, calcVOffsetT(3), 1));
            try testing.expectEqual(@as(u32, 8), tb.getSlot(u32, calcVOffsetT(4), 1));
            try testing.expectEqual(@as(u64, 10), tb.getSlot(u64, calcVOffsetT(5), 1));
            try testing.expectEqual(@as(i8, 12), tb.getSlot(i8, calcVOffsetT(6), 1));
            try testing.expectEqual(@as(i16, 14), tb.getSlot(i16, calcVOffsetT(7), 1));
            try testing.expectEqual(@as(i32, 16), tb.getSlot(i32, calcVOffsetT(8), 1));
            try testing.expectEqual(@as(i64, 18), tb.getSlot(i64, calcVOffsetT(9), 1));
            try testing.expectEqual(@as(f32, 20), tb.getSlot(f32, calcVOffsetT(10), 1));
            try testing.expectEqual(@as(f64, 22), tb.getSlot(f64, calcVOffsetT(11), 1));
            try testing.expectEqual(@as(u32, 24), tb.read(u32, calcUOffsetT(calcVOffsetT(12), tb)));
            try testing.expectEqual(@as(u16, 26), tb.read(u16, calcUOffsetT(calcVOffsetT(13), tb)));
            try testing.expectEqual(@as(i32, 28), tb.read(i32, calcUOffsetT(calcVOffsetT(14), tb)));
        }
    }.func;

    // make sure original values are okay
    try testForOriginalValues(t, uoVal, soVal);

    // try to mutate fields and check mutability
    try testMutability(t);

    // try to mutate fields and check mutability
    // these have wrong slots so should fail
    try testMutabilityWithoutSlot(t);

    // test whether values have changed
    try testForMutatedValues(t);
}

/// create len random valid utf8 strings w/ maxlen 256
fn createRandomStrings(alloc: mem.Allocator, len: usize, rand: std.rand.Random) ![]std.ArrayListUnmanaged(u8) {
    var strings = try alloc.alloc(std.ArrayListUnmanaged(u8), len);
    for (strings) |*s| {
        s.* = .{};
        const slen = rand.int(u8);
        var i: usize = 0;
        while (i < slen) {
            const c = rand.int(u21);
            const cplen = std.unicode.utf8CodepointSequenceLength(c) catch continue;
            if (i + cplen >= slen) break;
            var buf: [4]u8 = undefined;
            _ = std.unicode.utf8Encode(c, &buf) catch continue;
            try s.appendSlice(alloc, buf[0..cplen]);
            i += cplen;
        }
    }
    return strings;
}

fn checkSharedStrings(alloc: mem.Allocator) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    const len = 100;
    for (0..len) |_| {
        const strings = try createRandomStrings(alloc, len, rand);
        defer {
            for (strings) |*s| s.deinit(alloc);
            alloc.free(strings);
        }

        var b = Builder.init(alloc);
        defer b.deinitAll();
        for (strings) |l1| {
            const s1 = l1.items;
            for (strings) |l2| {
                const s2 = l2.items;
                const off1 = try b.createSharedString(s1);
                const off2 = try b.createSharedString(s2);
                try testing.expect(mem.eql(u8, s1, s2) == (off1 == off2));
            }
        }
    }
}

fn checkEmptiedBuilder(alloc: mem.Allocator) !void {
    var prng = std.rand.DefaultPrng.init(0);
    const rand = prng.random();
    const len = 100;
    const strings = try createRandomStrings(alloc, len, rand);
    defer {
        for (strings) |*s| s.deinit(alloc);
        alloc.free(strings);
    }
    for (strings) |l1| {
        const a = l1.items;
        for (strings) |l2| {
            const b = l2.items;
            if (mem.eql(u8, a, b)) continue;
            var builder = Builder.init(alloc);
            defer builder.deinitAll();

            const a1 = try builder.createSharedString(a);
            const b1 = try builder.createSharedString(b);
            builder.reset();
            const b2 = try builder.createSharedString(b);
            const a2 = try builder.createSharedString(a);

            try testing.expect(!(a1 == a2 or b1 == b2));
        }
    }
}

fn checkGetRootAsForNonRootTable(alloc: mem.Allocator) !void {
    var b = Builder.init(alloc);
    defer b.deinitAll();

    const str = try b.createString("MyStat");
    try Stat.Start(&b);
    try Stat.AddId(&b, str);
    try Stat.AddVal(&b, 12345678);
    try Stat.AddCount(&b, 12345);
    const stat_end = try Stat.End(&b);
    try b.finish(stat_end);

    const stat = Stat.GetRootAs(b.bytes.items, b.head);

    try testing.expectEqualStrings("MyStat", stat.Id());
    try testing.expectEqual(@as(i64, 12345678), stat.Val());
    try testing.expectEqual(@as(usize, 12345), stat.Count());
}

/// checks that the table accessors work as expected.
fn checkTableAccessors(alloc: mem.Allocator) !void {
    // test struct accessor
    var b = Builder.init(alloc);
    const pos = try Vec3.Create(&b, 1.0, 2.0, 3.0, 3.0, Color.Green, 5, 6);
    _ = try b.finish(pos);
    const vec3_bytes = try b.finishedBytes();
    const vec3 = fb.GetRootAs(Vec3, vec3_bytes, 0);
    try testing.expect(mem.eql(u8, vec3_bytes, vec3.Table().bytes));
    b.deinitAll();

    // test table accessor
    b = Builder.init(alloc);
    defer b.deinitAll();
    const str = try b.createString("MyStat");
    try Stat.Start(&b);
    try Stat.AddId(&b, str);
    try Stat.AddVal(&b, 12345678);
    try Stat.AddCount(&b, 12345);
    const pos2 = try Stat.End(&b);
    _ = try b.finish(pos2);
    const stat_bytes = try b.finishedBytes();
    const stat = Stat.GetRootAs(stat_bytes, 0);
    try testing.expect(mem.eql(u8, stat_bytes, stat.Table().bytes));
}

/// checks that the buffer is evaluated correctly as an example Monster.
fn checkReadBuffer(
    buf: []u8,
    offset: u32,
    sizePrefix: bool,
    file_identifier: ?[fb.Builder.file_identifier_len]u8,
) !void {
    if (file_identifier) |fid| {
        try testing.expectEqualStrings(&fid, fb.GetBufferIdentifier(buf, offset, sizePrefix));
        try testing.expect(fb.BufferHasIdentifier(buf, offset, fid, sizePrefix));
        if (sizePrefix)
            try testing.expect(Monster.SizePrefixedBufferHasIdentifier(buf, offset))
        else
            try testing.expect(Monster.BufferHasIdentifier(buf, offset));
    }

    // try the two ways of generating a monster
    const mons = if (sizePrefix) [_]Monster{
        Monster.GetSizePrefixedRootAs(buf, offset),
        fb.GetSizePrefixedRootAs(Monster, buf, offset),
    } else [_]Monster{
        Monster.GetRootAs(buf, offset),
        fb.GetRootAs(Monster, buf, offset),
    };

    for (mons, 0..) |monster, i| {
        try testing.expectEqual(@as(i16, 80), monster.Hp());
        // default
        try testing.expectEqual(@as(i16, 150), monster.Mana());
        try testing.expectEqualStrings("MyMonster", monster.Name());
        try testing.expectEqual(Color.Blue, monster.Color());
        try testing.expect(monster.Testbool());

        // initialize a Vec3 from Pos()
        const vec = monster.Pos() orelse return testing.expect(false);

        testing.expectApproxEqAbs(@as(f32, 1.0), vec.X(), std.math.f32_epsilon) catch |e| {
            std.log.err("Pox.X() != 1.0. i = {}", .{i});
            return e;
        };
        testing.expectApproxEqAbs(@as(f32, 2.0), vec.Y(), std.math.f32_epsilon) catch |e| {
            std.log.err("Pox.Y() != 2.0. i = {}", .{i});
            return e;
        };
        testing.expectApproxEqAbs(@as(f32, 3.0), vec.Z(), std.math.f32_epsilon) catch |e| {
            std.log.err("Pox.Z() != 3.0. i = {}", .{i});
            return e;
        };

        testing.expectApproxEqAbs(@as(f64, 3.0), vec.Test1(), std.math.f32_epsilon) catch |e| {
            std.log.err("Pox.Test1() != 3.0. i = {}", .{i});
            return e;
        };

        try testing.expectEqual(Color.Green, vec.Test2());

        const t = vec.Test3();

        try testing.expectEqual(@as(i16, 5), t.A());
        try testing.expectEqual(@as(i8, 6), t.B());

        try testing.expectEqual(Any.Tag.Monster, monster.TestType());

        // initialize a Table from a union field Test(...)
        const table2 = monster.Test();
        try testing.expect(table2 != null);

        // initialize a Monster from the Table from the union
        const monster2 = Monster.init(table2.?.bytes, table2.?.pos);

        try testing.expectEqualStrings("Fred", monster2.Name());

        const inventorySlice = monster.InventoryBytes();
        try testing.expectEqual(@as(usize, monster.InventoryLen()), inventorySlice.len);

        try testing.expectEqual(@as(u32, 5), monster.InventoryLen());

        var invsum: u32 = 0;
        for (0..monster.InventoryLen()) |j| {
            const v = monster.Inventory(j).?;
            try testing.expectEqual(inventorySlice[j], v);
            invsum += v;
        }
        try testing.expectEqual(@as(u32, 10), invsum);

        try testing.expectEqual(@as(u32, 2), monster.Test4Len());

        const test0 = monster.Test4(0) orelse return testing.expect(false);
        const test1 = monster.Test4(1) orelse return testing.expect(false);

        // the position of test0 and test1 are swapped in monsterdata_java_wire
        // and monsterdata_test_wire, so ignore ordering
        try testing.expectEqual(@as(i16, 100), test0.A() + test0.B() +
            test1.A() + test1.B());

        try testing.expectEqual(@as(usize, 2), monster.TestarrayofstringLen());

        try testing.expectEqualStrings("test1", monster.Testarrayofstring(0).?);

        try testing.expectEqualStrings("test2", monster.Testarrayofstring(1).?);
    }
}

// check that the given buffer can be mutated correctly
// as the example Monster. Only available scalar values are mutated.
fn checkMutateBuffer(
    alloc: mem.Allocator,
    org: []const u8,
    offset: u32,
    sizePrefix: bool,
) !void {
    // make a copy to mutate
    var buf = try alloc.dupe(u8, org);
    defer alloc.free(buf);

    // load monster data from the buffer
    var monster = if (sizePrefix)
        Monster.GetSizePrefixedRootAs(buf, offset)
    else
        Monster.GetRootAs(buf, offset);

    const testForOriginalValues = struct {
        fn func(mon: Monster) !void {
            try testing.expectEqual(@as(i16, 80), mon.Hp());
            try testing.expectEqual(@as(i16, 150), mon.Mana());
            try testing.expect(mon.Testbool());
            try testing.expectEqual(@as(f32, 1.0), mon.Pos().?.X());
            try testing.expectEqual(@as(f32, 2.0), mon.Pos().?.Y());
            try testing.expectEqual(@as(f32, 3.0), mon.Pos().?.Z());
            try testing.expectEqual(@as(f64, 3.0), mon.Pos().?.Test1());
            try testing.expectEqual(Color.Green, mon.Pos().?.Test2());
            try testing.expectEqual(@as(i16, 5), mon.Pos().?.Test3().A());
            try testing.expectEqual(@as(i8, 6), mon.Pos().?.Test3().B());
            try testing.expectEqual(@as(u8, 2), mon.Inventory(2).?);
        }
    }.func;

    const testMutability = struct {
        fn func(mon: Monster) !void {
            try testing.expect(mon.MutateHp(70));
            try testing.expect(!mon.MutateMana(140));
            try testing.expect(mon.MutateTestbool(false));
            try testing.expect(mon.Pos().?.MutateX(10.0));
            try testing.expect(mon.Pos().?.MutateY(20.0));
            try testing.expect(mon.Pos().?.MutateZ(30.0));
            try testing.expect(mon.Pos().?.MutateTest1(30.0));
            try testing.expect(mon.Pos().?.MutateTest2(.Blue));
            try testing.expect(mon.Pos().?.Test3().MutateA(50));
            try testing.expect(mon.Pos().?.Test3().MutateB(60));
            try testing.expect(mon.MutateInventory(2, 200));
        }
    }.func;

    const testForMutatedValues = struct {
        fn func(mon: Monster) !void {
            try testing.expectEqual(@as(i16, 70), mon.Hp());
            try testing.expectEqual(@as(i16, 150), mon.Mana());
            try testing.expect(!mon.Testbool());
            try testing.expectEqual(@as(f32, 10.0), mon.Pos().?.X());
            try testing.expectEqual(@as(f32, 20.0), mon.Pos().?.Y());
            try testing.expectEqual(@as(f32, 30.0), mon.Pos().?.Z());
            try testing.expectEqual(@as(f64, 30.0), mon.Pos().?.Test1());
            try testing.expectEqual(Color.Blue, mon.Pos().?.Test2());
            try testing.expectEqual(@as(i16, 50), mon.Pos().?.Test3().A());
            try testing.expectEqual(@as(i8, 60), mon.Pos().?.Test3().B());
            try testing.expectEqual(@as(u8, 200), mon.Inventory(2).?);
        }
    }.func;

    const testInvalidEnumValues = struct {
        fn func(mon: Monster) !void {
            _ = mon;
            // TODO?
            //     testcase{"Pos.Test2", func() bool { return monster.Pos(nil).MutateTest2(example.Color(20)) }},
            //     testcase{"Pos.Test2", func() bool { return monster.Pos(nil).Test2() == example.Color(20) }},
            // try testing.expect(mon.Pos().?.MutateTest2(@intToEnum(Color, 20)));
            // try testing.expectEqual(@intToEnum(Color, 20), mon.Pos().?.Test2());
        }
    }.func;

    // make sure original values are okay
    try testForOriginalValues(monster);

    // try to mutate fields and check mutability
    try testMutability(monster);

    // test whether values have changed
    try testForMutatedValues(monster);

    // make sure the buffer has changed
    try testing.expect(!mem.eql(u8, buf, org));

    // To make sure the buffer has changed accordingly
    // Read data from the buffer and verify all fields
    monster = if (sizePrefix)
        Monster.GetSizePrefixedRootAs(buf, offset)
    else
        Monster.GetRootAs(buf, offset);

    try testForMutatedValues(monster);

    // a couple extra tests for "invalid" enum values, which don't correspond to
    // anything in the schema, but are allowed
    try testInvalidEnumValues(monster);

    // reverting all fields to original values should
    // re-create the original buffer. Mutate all fields
    // back to their original values and compare buffers.
    // This test is done to make sure mutations do not do
    // any unnecessary changes to the buffer.
    monster = if (sizePrefix)
        Monster.GetSizePrefixedRootAs(buf, offset)
    else
        Monster.GetRootAs(buf, offset);

    _ = monster.MutateHp(80);
    _ = monster.MutateTestbool(true);
    _ = monster.Pos().?.MutateX(1.0);
    _ = monster.Pos().?.MutateY(2.0);
    _ = monster.Pos().?.MutateZ(3.0);
    _ = monster.Pos().?.MutateTest1(3.0);
    _ = monster.Pos().?.MutateTest2(.Green);
    _ = monster.Pos().?.Test3().MutateA(5);
    _ = monster.Pos().?.Test3().MutateB(6);
    _ = monster.MutateInventory(2, 2);

    try testForOriginalValues(monster);

    // buffer should have original values
    try testing.expect(mem.eql(u8, buf, org));
}

fn checkObjectAPI(
    alloc: mem.Allocator,
    buf: []u8,
    offset: u32,
    sizePrefix: bool,
) !void {
    const monster_ = if (sizePrefix)
        Monster.GetSizePrefixedRootAs(buf, offset)
    else
        Monster.GetRootAs(buf, offset);

    var monster = try monster_.Unpack(.{ .allocator = alloc });
    defer monster.deinit(alloc);

    try std.testing.expectEqual(@as(i16, 80), monster.hp);

    // default
    try std.testing.expectEqual(@as(i16, 150), monster.mana);

    if (monster.@"test" == .Monster) monster.@"test".Monster.?.nan_default = 0.0;
    if (monster.enemy) |x| x.nan_default = 0.0;
    monster.nan_default = 0.0;

    var builder = fb.Builder.init(alloc);
    defer builder.deinitAll();

    try builder.finish(try monster.Pack(&builder, .{ .allocator = alloc }));
    var monster2 = try Monster.GetRootAs(try builder.finishedBytes(), 0)
        .Unpack(.{ .allocator = alloc });
    defer monster2.deinit(alloc);
    // TODO use std.testing.expectEqualDeep() once
    // https://github.com/ziglang/zig/pull/14981 is merged
    try expectEqualDeep(monster, monster2);
}

/// verifies that vtables are deduplicated.
fn checkVtableDeduplication(alloc: mem.Allocator) !void {
    var b = Builder.init(alloc);
    defer b.deinitAll();

    try b.startObject(4);
    try b.prependSlot(u8, 0, 0, 0);
    try b.prependSlot(u8, 1, 11, 0);
    try b.prependSlot(u8, 2, 22, 0);
    try b.prependSlot(i16, 3, 33, 0);
    const obj0 = try b.endObject();

    try b.startObject(4);
    try b.prependSlot(u8, 0, 0, 0);
    try b.prependSlot(u8, 1, 44, 0);
    try b.prependSlot(u8, 2, 55, 0);
    try b.prependSlot(i16, 3, 66, 0);
    const obj1 = try b.endObject();

    try b.startObject(4);
    try b.prependSlot(u8, 0, 0, 0);
    try b.prependSlot(u8, 1, 77, 0);
    try b.prependSlot(u8, 2, 88, 0);
    try b.prependSlot(i16, 3, 99, 0);
    const obj2 = try b.endObject();

    const got = b.bytes.items[b.head..];

    const want = [_]u8{
        240, 255, 255, 255, // == -12. offset to dedupped vtable.
        99,  0,   88,  77,
        248, 255, 255, 255, // == -8. offset to dedupped vtable.
        66,  0,   55,  44,
        12,  0,   8,   0,
        0,   0,   7,   0,
        6,   0,   4,   0,
        12,  0,   0,   0,
        33,  0,   22,  11,
    };

    try testing.expectEqualSlices(u8, &want, got);

    const table0 = fb.Table{ .bytes = b.bytes.items, .pos = @intCast(u32, b.bytes.items.len) - obj0 };
    const table1 = fb.Table{ .bytes = b.bytes.items, .pos = @intCast(u32, b.bytes.items.len) - obj1 };
    const table2 = fb.Table{ .bytes = b.bytes.items, .pos = @intCast(u32, b.bytes.items.len) - obj2 };

    const testTable = struct {
        fn func(tab: fb.Table, a: u16, b_: u8, c: u8, d: u8) !void {
            // vtable size
            try testing.expectEqual(@as(u16, 12), tab.getSlotOff(u16, 0, 0));
            // object size
            try testing.expectEqual(@as(u16, 8), tab.getSlotOff(u16, 2, 0));
            // default value
            try testing.expectEqual(@as(u16, a), tab.getSlot(u8, 4, 0));
            try testing.expectEqual(@as(u16, b_), tab.getSlot(u8, 6, 0));
            try testing.expectEqual(@as(u16, c), tab.getSlot(u8, 8, 0));
            try testing.expectEqual(@as(u16, d), tab.getSlot(u8, 10, 0));
        }
    }.func;

    try testTable(table0, 0, 11, 22, 33);
    try testTable(table1, 0, 44, 55, 66);
    try testTable(table2, 0, 77, 88, 99);
}

// checks that the generated enum names are correct.
fn checkEnumNamesAndValues() !void {
    {
        const fields = comptime std.meta.fields(Any.Tag);
        try testing.expectEqualStrings("NONE", fields[0].name);
        try testing.expectEqual(@enumToInt(Any.Tag.NONE), fields[0].value);
        try testing.expectEqualStrings("Monster", fields[1].name);
        try testing.expectEqual(@enumToInt(Any.Tag.Monster), fields[1].value);
        try testing.expectEqualStrings("TestSimpleTableWithEnum", fields[2].name);
        try testing.expectEqual(@enumToInt(Any.Tag.TestSimpleTableWithEnum), fields[2].value);
        try testing.expectEqualStrings("MyGame_Example2_Monster", fields[3].name);
        try testing.expectEqual(@enumToInt(Any.Tag.MyGame_Example2_Monster), fields[3].value);
    }
    {
        const fields = comptime std.meta.fields(Color);
        try testing.expectEqualStrings("Red", fields[0].name);
        try testing.expectEqual(@enumToInt(Color.Red), fields[0].value);
        try testing.expectEqualStrings("Green", fields[1].name);
        try testing.expectEqual(@enumToInt(Color.Green), fields[1].value);
        try testing.expectEqualStrings("Blue", fields[2].name);
        try testing.expectEqual(@enumToInt(Color.Blue), fields[2].value);
    }
}

fn checkCreateByteVector(alloc: mem.Allocator) !void {
    const raw: [30]u8 = std.simd.iota(u8, 30);

    for (0..raw.len) |size| {
        var b1 = Builder.init(alloc);
        defer b1.deinitAll();
        var b2 = Builder.init(alloc);
        defer b2.deinitAll();
        _ = try b1.startVector(1, @intCast(i32, size), 1);
        var i = @intCast(isize, size) - 1;
        while (i >= 0) : (i -= 1)
            try b1.prepend(u8, raw[@bitCast(usize, i)]);

        _ = try b1.endVector(@intCast(u32, size));
        _ = try b2.createByteVector(raw[0..size]);
        try testing.expectEqualStrings(b1.bytes.items, b2.bytes.items);
    }
}

fn checkParentNamespace(alloc: mem.Allocator) !void {
    // create monster with an empty parent namespace field
    const empty = blk: {
        var builder = Builder.init(alloc);
        defer builder.deinitAll();

        try Monster.Start(&builder);
        const m = try Monster.End(&builder);
        try builder.finish(m);

        break :blk try alloc.dupe(u8, try builder.finishedBytes());
    };
    defer alloc.free(empty);

    // create monster with a non-empty parent namespace field
    const nonempty = blk: {
        var builder = Builder.init(alloc);
        defer builder.deinitAll();

        try InParentNamespace.Start(&builder);
        const pn = try InParentNamespace.End(&builder);

        try Monster.Start(&builder);

        try Monster.AddParentNamespaceTest(&builder, pn);
        const m = try Monster.End(&builder);

        try builder.finish(m);

        break :blk try alloc.dupe(u8, try builder.finishedBytes());
    };
    defer alloc.free(nonempty);

    // read monster with empty parent namespace field
    {
        const m = Monster.GetRootAs(empty, 0);
        try testing.expect(m.ParentNamespaceTest() == null);
    }

    // read monster with non-empty parent namespace field
    {
        const m = Monster.GetRootAs(nonempty, 0);
        try testing.expect(m.ParentNamespaceTest() != null);
    }
}

fn checkNoNamespaceImport(alloc: mem.Allocator) !void {
    const size = 13;
    // Order a pizza with specific size
    var builder = Builder.init(alloc);
    defer builder.deinitAll();

    var ordered_pizza = PizzaT{ .size = size };
    const food = FoodT{ .pizza = &ordered_pizza };
    try builder.finish(try food.Pack(&builder, .{ .allocator = alloc }));

    // Receive order
    const received_food = Food.GetRootAs(try builder.finishedBytes(), 0);
    const received_pizza = try received_food.Pizza_().?.Unpack(.{ .allocator = alloc });

    try expectEqualDeep(ordered_pizza, received_pizza);
}

fn checkSizePrefixedBuffer(alloc: mem.Allocator) !void {
    // Generate a size-prefixed flatbuffer
    const gen_off = try checkGeneratedBuild(alloc, true, null);
    const generated = gen_off[0];
    defer alloc.free(generated);
    const off = gen_off[1];

    // Check that the size prefix is the size of monsterdata_go_wire.mon minus 4
    const size = fb.GetSizePrefix(generated, off);
    try testing.expectEqual(@as(usize, 220), size);

    // Check that the buffer can be used as expected
    try checkReadBuffer(generated, off, true, null);
    try checkMutateBuffer(alloc, generated, off, true);
    try checkObjectAPI(alloc, generated, off, true);

    // Write generated bfufer out to a file
    // if err := ioutil.WriteFile(outData+".sp", generated[off:], os.FileMode(0644)); err != nil {
    //     std.log.err("failed to write file: %s", err)
    // }
}

// verifies against the ScalarStuff schema.
fn checkOptionalScalars(alloc: mem.Allocator) !void {
    const makeDefaultTestCases = struct {
        fn func(s: ScalarStuff) !void {
            try testing.expectEqual(@as(i8, 0), s.JustI8());
            try testing.expectEqual(@as(?i8, null), s.MaybeI8());
            try testing.expectEqual(@as(i8, 42), s.DefaultI8());
            try testing.expectEqual(@as(u8, 0), s.JustU8());
            try testing.expectEqual(@as(?u8, null), s.MaybeU8());
            try testing.expectEqual(@as(u8, 42), s.DefaultU8());
            try testing.expectEqual(@as(i16, 0), s.JustI16());
            try testing.expectEqual(@as(?i16, null), s.MaybeI16());
            try testing.expectEqual(@as(i16, 42), s.DefaultI16());
            try testing.expectEqual(@as(u16, 0), s.JustU16());
            try testing.expectEqual(@as(?u16, null), s.MaybeU16());
            try testing.expectEqual(@as(u16, 42), s.DefaultU16());
            try testing.expectEqual(@as(i32, 0), s.JustI32());
            try testing.expectEqual(@as(?i32, null), s.MaybeI32());
            try testing.expectEqual(@as(i32, 42), s.DefaultI32());
            try testing.expectEqual(@as(u32, 0), s.JustU32());
            try testing.expectEqual(@as(?u32, null), s.MaybeU32());
            try testing.expectEqual(@as(u32, 42), s.DefaultU32());
            try testing.expectEqual(@as(i64, 0), s.JustI64());
            try testing.expectEqual(@as(?i64, null), s.MaybeI64());
            try testing.expectEqual(@as(i64, 42), s.DefaultI64());
            try testing.expectEqual(@as(u64, 0), s.JustU64());
            try testing.expectEqual(@as(?u64, null), s.MaybeU64());
            try testing.expectEqual(@as(u64, 42), s.DefaultU64());
            try testing.expectEqual(@as(f32, 0), s.JustF32());
            try testing.expectEqual(@as(?f32, null), s.MaybeF32());
            try testing.expectEqual(@as(f32, 42), s.DefaultF32());
            try testing.expectEqual(@as(f64, 0), s.JustF64());
            try testing.expectEqual(@as(?f64, null), s.MaybeF64());
            try testing.expectEqual(@as(f64, 42), s.DefaultF64());
            try testing.expect(!s.JustBool());
            try testing.expectEqual(@as(?bool, null), s.MaybeBool());
            try testing.expect(s.DefaultBool());
            try testing.expectEqual(OptionalByte.None, s.JustEnum());
            try testing.expectEqual(@as(?OptionalByte, null), s.MaybeEnum());
            try testing.expectEqual(OptionalByte.One, s.DefaultEnum());
        }
    }.func;

    const makeAssignedTestCases = struct {
        fn func(s: ScalarStuff) !void {
            try testing.expectEqual(@as(i8, 5), s.JustI8());
            try testing.expectEqual(@as(?i8, 5), s.MaybeI8());
            try testing.expectEqual(@as(i8, 5), s.DefaultI8());
            try testing.expectEqual(@as(u8, 6), s.JustU8());
            try testing.expectEqual(@as(?u8, 6), s.MaybeU8());
            try testing.expectEqual(@as(u8, 6), s.DefaultU8());
            try testing.expectEqual(@as(i16, 7), s.JustI16());
            try testing.expectEqual(@as(?i16, 7), s.MaybeI16());
            try testing.expectEqual(@as(i16, 7), s.DefaultI16());
            try testing.expectEqual(@as(u16, 8), s.JustU16());
            try testing.expectEqual(@as(?u16, 8), s.MaybeU16());
            try testing.expectEqual(@as(u16, 8), s.DefaultU16());
            try testing.expectEqual(@as(i32, 9), s.JustI32());
            try testing.expectEqual(@as(?i32, 9), s.MaybeI32());
            try testing.expectEqual(@as(i32, 9), s.DefaultI32());
            try testing.expectEqual(@as(u32, 10), s.JustU32());
            try testing.expectEqual(@as(?u32, 10), s.MaybeU32());
            try testing.expectEqual(@as(u32, 10), s.DefaultU32());
            try testing.expectEqual(@as(i64, 11), s.JustI64());
            try testing.expectEqual(@as(?i64, 11), s.MaybeI64());
            try testing.expectEqual(@as(i64, 11), s.DefaultI64());
            try testing.expectEqual(@as(u64, 12), s.JustU64());
            try testing.expectEqual(@as(?u64, 12), s.MaybeU64());
            try testing.expectEqual(@as(u64, 12), s.DefaultU64());
            try testing.expectEqual(@as(f32, 13), s.JustF32());
            try testing.expectEqual(@as(?f32, 13), s.MaybeF32());
            try testing.expectEqual(@as(f32, 13), s.DefaultF32());
            try testing.expectEqual(@as(f64, 14), s.JustF64());
            try testing.expectEqual(@as(?f64, 14), s.MaybeF64());
            try testing.expectEqual(@as(f64, 14), s.DefaultF64());
            try testing.expect(s.JustBool());
            try testing.expectEqual(@as(?bool, true), s.MaybeBool());
            try testing.expect(!s.DefaultBool());
            try testing.expectEqual(OptionalByte.Two, s.JustEnum());
            try testing.expectEqual(@as(?OptionalByte, OptionalByte.Two), s.MaybeEnum());
            try testing.expectEqual(OptionalByte.Two, s.DefaultEnum());
        }
    }.func;

    const buildAssignedTable = struct {
        fn func(b: *Builder) !ScalarStuff {
            try ScalarStuff.Start(b);
            try ScalarStuff.AddJustI8(b, 5);
            try ScalarStuff.AddMaybeI8(b, 5);
            try ScalarStuff.AddDefaultI8(b, 5);
            try ScalarStuff.AddJustU8(b, 6);
            try ScalarStuff.AddMaybeU8(b, 6);
            try ScalarStuff.AddDefaultU8(b, 6);
            try ScalarStuff.AddJustI16(b, 7);
            try ScalarStuff.AddMaybeI16(b, 7);
            try ScalarStuff.AddDefaultI16(b, 7);
            try ScalarStuff.AddJustU16(b, 8);
            try ScalarStuff.AddMaybeU16(b, 8);
            try ScalarStuff.AddDefaultU16(b, 8);
            try ScalarStuff.AddJustI32(b, 9);
            try ScalarStuff.AddMaybeI32(b, 9);
            try ScalarStuff.AddDefaultI32(b, 9);
            try ScalarStuff.AddJustU32(b, 10);
            try ScalarStuff.AddMaybeU32(b, 10);
            try ScalarStuff.AddDefaultU32(b, 10);
            try ScalarStuff.AddJustI64(b, 11);
            try ScalarStuff.AddMaybeI64(b, 11);
            try ScalarStuff.AddDefaultI64(b, 11);
            try ScalarStuff.AddJustU64(b, 12);
            try ScalarStuff.AddMaybeU64(b, 12);
            try ScalarStuff.AddDefaultU64(b, 12);
            try ScalarStuff.AddJustF32(b, 13);
            try ScalarStuff.AddMaybeF32(b, 13);
            try ScalarStuff.AddDefaultF32(b, 13);
            try ScalarStuff.AddJustF64(b, 14);
            try ScalarStuff.AddMaybeF64(b, 14);
            try ScalarStuff.AddDefaultF64(b, 14);
            try ScalarStuff.AddJustBool(b, true);
            try ScalarStuff.AddMaybeBool(b, true);
            try ScalarStuff.AddDefaultBool(b, false);
            try ScalarStuff.AddJustEnum(b, .Two);
            try ScalarStuff.AddMaybeEnum(b, .Two);
            try ScalarStuff.AddDefaultEnum(b, .Two);
            try b.finish(try ScalarStuff.End(b));
            return ScalarStuff.GetRootAs(try b.finishedBytes(), 0);
        }
    }.func;

    // test default values
    var fbb = try Builder.initCapacity(alloc, 1);
    defer fbb.deinitAll();
    try ScalarStuff.Start(&fbb);
    try fbb.finish(try ScalarStuff.End(&fbb));
    var ss = ScalarStuff.GetRootAs(try fbb.finishedBytes(), 0);
    try makeDefaultTestCases(ss);

    // test assigned values
    fbb.reset();
    ss = try buildAssignedTable(&fbb);
    try makeAssignedTestCases(ss);

    // test native object pack
    fbb.reset();
    var obj = ScalarStuffT{
        .just_i8 = 5,
        .maybe_i8 = 5,
        .default_i8 = 5,
        .just_u8 = 6,
        .maybe_u8 = 6,
        .default_u8 = 6,
        .just_i16 = 7,
        .maybe_i16 = 7,
        .default_i16 = 7,
        .just_u16 = 8,
        .maybe_u16 = 8,
        .default_u16 = 8,
        .just_i32 = 9,
        .maybe_i32 = 9,
        .default_i32 = 9,
        .just_u32 = 10,
        .maybe_u32 = 10,
        .default_u32 = 10,
        .just_i64 = 11,
        .maybe_i64 = 11,
        .default_i64 = 11,
        .just_u64 = 12,
        .maybe_u64 = 12,
        .default_u64 = 12,
        .just_f32 = 13,
        .maybe_f32 = 13,
        .default_f32 = 13,
        .just_f64 = 14,
        .maybe_f64 = 14,
        .default_f64 = 14,
        .just_bool = true,
        .maybe_bool = true,
        .default_bool = false,
        .just_enum = .Two,
        .maybe_enum = .Two,
        .default_enum = .Two,
    };

    try fbb.finish(try obj.Pack(&fbb, .{}));
    ss = ScalarStuff.GetRootAs(try fbb.finishedBytes(), 0);
    try makeAssignedTestCases(ss);

    // test native object unpack
    fbb.reset();
    ss = try buildAssignedTable(&fbb);
    try ScalarStuffT.UnpackTo(ss, &obj, .{});
    try testing.expectEqual(@as(i8, 5), obj.just_i8);
    try testing.expectEqual(@as(?i8, 5), obj.maybe_i8);
    try testing.expectEqual(@as(i8, 5), obj.default_i8);
    try testing.expectEqual(@as(u8, 6), obj.just_u8);
    try testing.expectEqual(@as(?u8, 6), obj.maybe_u8);
    try testing.expectEqual(@as(u8, 6), obj.default_u8);
    try testing.expectEqual(@as(i16, 7), obj.just_i16);
    try testing.expectEqual(@as(?i16, 7), obj.maybe_i16);
    try testing.expectEqual(@as(i16, 7), obj.default_i16);
    try testing.expectEqual(@as(u16, 8), obj.just_u16);
    try testing.expectEqual(@as(?u16, 8), obj.maybe_u16);
    try testing.expectEqual(@as(u16, 8), obj.default_u16);
    try testing.expectEqual(@as(i32, 9), obj.just_i32);
    try testing.expectEqual(@as(?i32, 9), obj.maybe_i32);
    try testing.expectEqual(@as(i32, 9), obj.default_i32);
    try testing.expectEqual(@as(u32, 10), obj.just_u32);
    try testing.expectEqual(@as(?u32, 10), obj.maybe_u32);
    try testing.expectEqual(@as(u32, 10), obj.default_u32);
    try testing.expectEqual(@as(i64, 11), obj.just_i64);
    try testing.expectEqual(@as(?i64, 11), obj.maybe_i64);
    try testing.expectEqual(@as(i64, 11), obj.default_i64);
    try testing.expectEqual(@as(u64, 12), obj.just_u64);
    try testing.expectEqual(@as(?u64, 12), obj.maybe_u64);
    try testing.expectEqual(@as(u64, 12), obj.default_u64);
    try testing.expectEqual(@as(f32, 13), obj.just_f32);
    try testing.expectEqual(@as(?f32, 13), obj.maybe_f32);
    try testing.expectEqual(@as(f32, 13), obj.default_f32);
    try testing.expectEqual(@as(f64, 14), obj.just_f64);
    try testing.expectEqual(@as(?f64, 14), obj.maybe_f64);
    try testing.expectEqual(@as(f64, 14), obj.default_f64);
    try testing.expect(obj.just_bool);
    try testing.expectEqual(@as(?bool, true), obj.maybe_bool);
    try testing.expect(!obj.default_bool);
    try testing.expectEqual(OptionalByte.Two, obj.just_enum);
    try testing.expectEqual(@as(?OptionalByte, OptionalByte.Two), obj.maybe_enum);
    try testing.expectEqual(OptionalByte.Two, obj.default_enum);
}

fn checkByKey(alloc: mem.Allocator) !void {
    var b = Builder.init(alloc);
    defer b.deinitAll();
    const name = try b.createString("Boss");

    const slime = MonsterT{ .name = "Slime" };
    const pig = MonsterT{ .name = "Pig" };
    const slimeBoss = MonsterT{ .name = "SlimeBoss" };
    const mushroom = MonsterT{ .name = "Mushroom" };
    const ironPig = MonsterT{ .name = "Iron Pig" };

    var monsterOffsets: [5]u32 = .{
        try slime.Pack(&b, .{}),
        try pig.Pack(&b, .{}),
        try slimeBoss.Pack(&b, .{}),
        try mushroom.Pack(&b, .{}),
        try ironPig.Pack(&b, .{}),
    };
    const testarrayoftables =
        try b.createVectorOfSortedTables(&monsterOffsets, Monster.KeyCompare);

    const str = StatT{ .id = "Strength", .count = 42 };
    const luk = StatT{ .id = "Luck", .count = 51 };
    const hp = StatT{ .id = "Health", .count = 12 };
    // Test default count value of 0
    const mp = StatT{ .id = "Mana" };

    var statOffsets: [4]u32 = .{
        try str.Pack(&b, .{}),
        try luk.Pack(&b, .{}),
        try hp.Pack(&b, .{}),
        try mp.Pack(&b, .{}),
    };
    const scalarKeySortedTablesOffset =
        try b.createVectorOfSortedTables(&statOffsets, Stat.KeyCompare);

    try Monster.Start(&b);
    try Monster.AddName(&b, name);
    try Monster.AddTestarrayoftables(&b, testarrayoftables);
    try Monster.AddScalarKeySortedTables(&b, scalarKeySortedTablesOffset);
    const moff = try Monster.End(&b);
    try b.finish(moff);

    const monster = Monster.GetRootAs(b.bytes.items, b.head);
    var slimeMon: Monster = undefined;
    try testing.expect(monster.TestarrayoftablesByKey(&slimeMon, slime.name));
    var mushroomMon: Monster = undefined;
    try testing.expect(monster.TestarrayoftablesByKey(&mushroomMon, mushroom.name));
    var slimeBossMon: Monster = undefined;
    try testing.expect(monster.TestarrayoftablesByKey(&slimeBossMon, slimeBoss.name));

    var strStat: Stat = undefined;
    try testing.expect(monster.ScalarKeySortedTablesByKey(&strStat, str.count));
    var lukStat: Stat = undefined;
    try testing.expect(monster.ScalarKeySortedTablesByKey(&lukStat, luk.count));
    var mpStat: Stat = undefined;
    try testing.expect(monster.ScalarKeySortedTablesByKey(&mpStat, mp.count));

    try testing.expectEqualStrings("Boss", monster.Name());
    try testing.expectEqualStrings(slime.name, slimeMon.Name());
    try testing.expectEqualStrings(mushroom.name, mushroomMon.Name());
    try testing.expectEqualStrings(slimeBoss.name, slimeBossMon.Name());
    try testing.expectEqualStrings(str.id, strStat.Id());
    try testing.expectEqual(str.count, strStat.Count());
    try testing.expectEqualStrings(luk.id, lukStat.Id());
    try testing.expectEqual(luk.count, lukStat.Count());
    try testing.expectEqualStrings(mp.id, mpStat.Id());
    // Use default count value as key
    try testing.expectEqual(@as(u16, 0), mpStat.Count());
}

/// simple random number generator to ensure results will be the
/// same cross platform.
/// http://en.wikipedia.org/wiki/Park%E2%80%93Miller_random_number_generator
const LCG = struct {
    val: u32,
    const InitialLCGSeed = 48271;
    pub fn init() LCG {
        return .{ .val = InitialLCGSeed };
    }

    pub fn reset(lcg: *LCG) void {
        lcg.val = InitialLCGSeed;
    }

    pub fn next(lcg: *LCG) u32 {
        const n = @truncate(u32, @as(u64, lcg.val) * @truncate(u32, @as(u64, 279470273) % @as(u64, 4294967291)));
        lcg.val = n;
        return n;
    }
};

const overflowingInt32Val = fb.encode.read(i32, &.{ 0x83, 0x33, 0x33, 0x33 });
const overflowingInt64Val = fb.encode.read(i64, &.{ 0x84, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44 });

fn checkFuzz(alloc: mem.Allocator, fuzzFields: u32, fuzzObjects: u32) !void {
    // Values we're testing against: chosen to ensure no bits get chopped
    // off anywhere, and also be different from eachother.
    const boolVal = true;
    const int8Val: i8 = -127; // 0x81
    const uint8Val: u8 = 0xFF;
    const int16Val: i16 = -32222; // 0x8222
    const uint16Val: u16 = 0xFEEE;
    const int32Val: i32 = overflowingInt32Val;
    const uint32Val: u32 = 0xFDDDDDDD;
    const int64Val: i64 = overflowingInt64Val;
    const uint64Val: u64 = 0xFCCCCCCCCCCCCCCC;
    const float32Val: f32 = 3.14159;
    const float64Val: f64 = 3.14159265359;

    const testValuesMax = 11; // hardcoded to the number of scalar types

    var builder = Builder.init(alloc);
    defer builder.deinitAll();
    var l = LCG.init();

    var objects = try alloc.alloc(u32, fuzzObjects);
    defer alloc.free(objects);

    // Generate fuzzObjects random objects each consisting of
    // fuzzFields fields, each of a random type.
    for (0..fuzzObjects) |i| {
        try builder.startObject(fuzzFields);

        for (0..fuzzFields) |f_| {
            const f = @intCast(u32, f_);
            const choice = l.next() % testValuesMax;
            try switch (choice) {
                0 => builder.prependSlot(bool, f, boolVal, false),
                1 => builder.prependSlot(i8, f, int8Val, 0),
                2 => builder.prependSlot(u8, f, uint8Val, 0),
                3 => builder.prependSlot(i16, f, int16Val, 0),
                4 => builder.prependSlot(u16, f, uint16Val, 0),
                5 => builder.prependSlot(i32, f, int32Val, 0),
                6 => builder.prependSlot(u32, f, uint32Val, 0),
                7 => builder.prependSlot(i64, f, int64Val, 0),
                8 => builder.prependSlot(u64, f, uint64Val, 0),
                9 => builder.prependSlot(f32, f, float32Val, 0),
                10 => builder.prependSlot(f64, f, float64Val, 0),
                else => unreachable,
            };
        }

        const off = try builder.endObject();

        // store the offset from the end of the builder buffer,
        // since it will keep growing:
        objects[i] = off;
    }

    // Do some bookkeeping to generate stats on fuzzes:
    var stats = std.StringArrayHashMap(i32).init(alloc);
    defer stats.deinit();

    const _check = struct {
        fn func(desc: []const u8, want: anytype, got: anytype, stats_: *std.StringArrayHashMap(i32)) !void {
            const gop = try stats_.getOrPut(desc);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
            try testing.expectEqual(want, got);
        }
    }.func;

    l = LCG.init(); // Reset.

    // Test that all objects we generated are readable and return the
    // expected values. We generate random objects in the same order
    // so this is deterministic.
    for (0..fuzzObjects) |i| {
        const table = fb.Table{
            .bytes = builder.bytes.items,
            .pos = @intCast(u32, builder.bytes.items.len) - objects[i],
        };

        for (0..fuzzFields) |j| {
            const f = @intCast(u16, (fb.encode.vtable_metadata_fields + j) * fb.Builder.size_u16);
            const choice = l.next() % testValuesMax;

            switch (choice) {
                0 => try _check("bool", boolVal, table.getSlot(bool, f, false), &stats),
                1 => try _check("int8", int8Val, table.getSlot(i8, f, 0), &stats),
                2 => try _check("uint8", uint8Val, table.getSlot(u8, f, 0), &stats),
                3 => try _check("int16", int16Val, table.getSlot(i16, f, 0), &stats),
                4 => try _check("uint16", uint16Val, table.getSlot(u16, f, 0), &stats),
                5 => try _check("int32", int32Val, table.getSlot(i32, f, 0), &stats),
                6 => try _check("uint32", uint32Val, table.getSlot(u32, f, 0), &stats),
                7 => try _check("int64", int64Val, table.getSlot(i64, f, 0), &stats),
                8 => try _check("uint64", uint64Val, table.getSlot(u64, f, 0), &stats),
                9 => try _check("float32", float32Val, table.getSlot(f32, f, 0), &stats),
                10 => try _check("float64", float64Val, table.getSlot(f64, f, 0), &stats),
                else => unreachable,
            }
        }
    }

    // If enough checks were made, verify that all scalar types were used:
    if (fuzzFields * fuzzObjects >= testValuesMax) {
        if (stats.count() != testValuesMax) {
            std.log.err("fuzzing failed to test all scalar types", .{});
            try testing.expect(false);
        }
    }

    // Print some counts, if needed:
    std.log.info("\nfuzzing results:\n", .{});
    if (fuzzFields == 0 or fuzzObjects == 0)
        std.log.info(
            "fuzz\tfields: {}\tobjects: {}\t[none]\t{}\n",
            .{ fuzzFields, fuzzObjects, 0 },
        )
    else {
        var ctx: SortCtx = .{ .keys = stats.keys() };
        stats.sort(ctx);
        for (stats.keys(), 0..) |k, i| {
            std.log.info(
                "fuzz\tfields: {}\tobjects: {}\t{s}\t{}\n",
                .{ fuzzFields, fuzzObjects, k, stats.values()[i] },
            );
        }
    }
}

const SortCtx = struct {
    keys: []const []const u8,
    pub fn lessThan(self: SortCtx, a: usize, b: usize) bool {
        return mem.lessThan(u8, self.keys[a], self.keys[b]);
    }
};

/// ported from flatbuffers/tests/py_test.py#TestWireFormat()
/// Verifies the generated zig code's buffer for all combos of
///   size_prefixed: true, false
///   file_identifier: ==null, !=null
fn checkWireFormat(alloc: mem.Allocator) !void {
    for ([_]bool{ true, false }) |size_prefixed| {
        for ([_]?[4]u8{ null, "MONS".* }) |file_identifier| {
            const gen_off = try checkGeneratedBuild(alloc, size_prefixed, file_identifier);
            const generated = gen_off[0];
            defer talloc.free(generated);
            const off = gen_off[1];
            try checkReadBuffer(generated, off, size_prefixed, file_identifier);
        }
    }

    // Verify that the canonical flatbuffer file is readable by the
    // generated zig code.
    const canonicalWireData = try std.fs.cwd().readFileAlloc(
        talloc,
        "examples/monsterdata_test.mon",
        std.math.maxInt(u32),
    );
    defer talloc.free(canonicalWireData);

    try checkReadBuffer(canonicalWireData, 0, false, "MONS".*);
}

const talloc = testing.allocator;

test checkByteLayout {
    // Verify that the zig library generates the
    // expected bytes (does not use any schema):
    try checkByteLayout(talloc);
    try checkMutateMethods(talloc);
}

test checkSharedStrings {
    // Verify shared strings behavior
    try checkSharedStrings(talloc);
    try checkEmptiedBuilder(talloc);
}

test checkGetRootAsForNonRootTable {
    // Verify that GetRootAs works for non-root tables
    try checkGetRootAsForNonRootTable(talloc);
    try checkTableAccessors(talloc);
}

test checkGeneratedBuild {
    // Verify that using the generated code builds a buffer without
    // returning errors:
    const gen_off = try checkGeneratedBuild(talloc, false, null);
    const generated = gen_off[0];
    defer talloc.free(generated);
    const off = gen_off[1];

    // Verify that the buffer generated by zig code is readable by the
    // generated code
    try checkReadBuffer(generated, off, false, null);
    try checkMutateBuffer(talloc, generated, off, false);
    try checkObjectAPI(talloc, generated, off, false);
}

test "monster_data_cpp" {
    // Verify that the buffer generated by C++ code is readable by the
    // generated zig code:
    const monster_data_cpp = try std.fs.cwd().readFileAlloc(
        talloc,
        "examples/monsterdata_test.mon",
        std.math.maxInt(u32),
    );
    defer talloc.free(monster_data_cpp);

    try checkReadBuffer(monster_data_cpp, 0, false, null);
    try checkMutateBuffer(talloc, monster_data_cpp, 0, false);
    try checkObjectAPI(talloc, monster_data_cpp, 0, false);
}

test checkVtableDeduplication {
    // Verify that vtables are deduplicated when written:
    try checkVtableDeduplication(talloc);
}

test checkEnumNamesAndValues {
    // Verify the enum names
    try checkEnumNamesAndValues();
}

test checkCreateByteVector {
    // Check Builder.CreateByteVector
    try checkCreateByteVector(talloc);
}

test checkParentNamespace {
    // Check a parent namespace import
    try checkParentNamespace(talloc);
}

test checkNoNamespaceImport {
    // Check a no namespace import
    try checkNoNamespaceImport(talloc);
}

test checkSizePrefixedBuffer {
    // Check size-prefixed flatbuffers
    try checkSizePrefixedBuffer(talloc);
}

test checkOptionalScalars {
    // Check that optional scalars works
    try checkOptionalScalars(talloc);
}

test checkByKey {
    // Check that getting vector element by key works
    try checkByKey(talloc);
}

test checkFuzz {
    // Verify that various fuzzing scenarios produce a valid FlatBuffer.
    try checkFuzz(talloc, 4, 10_000);
}

test checkWireFormat {
    try checkWireFormat(talloc);
}
