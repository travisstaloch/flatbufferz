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
const InParentNamespace = gen.MyGame_InParentNamespace.InParentNamespace;
const PizzaT = gen.Pizza.PizzaT;
const FoodT = gen.order_Food.FoodT;
const Food = gen.order_Food.Food;

const Fail = fn (comptime []const u8, anytype) void;
const expectEqualDeep = @import("testing.zig").expectEqualDeep;

// build an example Monster. returns (buf,offset)
fn checkGeneratedBuild(
    alloc: mem.Allocator,
    sizePrefix: bool,
    comptime fail: Fail,
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
    const inv = b.endVector(5);

    try Monster.Start(&b);
    try Monster.AddName(&b, fred);
    const mon2 = try Monster.End(&b);

    _ = try Monster.StartTest4Vector(&b, 2);
    _ = try Test.Create(&b, 10, 20);
    _ = try Test.Create(&b, 30, 40);
    const test4 = b.endVector(2);

    _ = try Monster.StartTestarrayofstringVector(&b, 2);
    try b.prependUOff(test2);
    try b.prependUOff(test1);
    const testArrayOfString = b.endVector(2);

    try Monster.Start(&b);

    const pos = try Vec3.Create(&b, 1.0, 2.0, 3.0, 3.0, .Green, 5, 6);
    Monster.AddPos(&b, pos);

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
        // b.FinishSizePrefixed(mon);
        fail("TODO b.FinishSizePrefixed()", .{});
    } else {
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
        _ = b.endVector(1);
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
        _ = b.endVector(2);
        try check(&[_]u8{ 2, 0, 0, 0, 2, 1, 0, 0 }, b, &i); // paddin
    }
    { // test 3b: 11xbyte vector matches builder size
        var b = Builder.init(alloc);
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
        _ = b.endVector(8);
        try start.insertSlice(0, &.{ 8, 0, 0, 0 });
        try check(start.items, b, &i);
    }

    { // test 4: 1xuint16 vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_u16, 1, 1);
        try check(&[_]u8{ 0, 0 }, b, &i); // align to 4byte
        try b.prepend(u16, 1);
        try check(&[_]u8{ 1, 0, 0, 0 }, b, &i);
        _ = b.endVector(1);
        try check(&[_]u8{ 1, 0, 0, 0, 1, 0, 0, 0 }, b, &i); // paddin
    }

    { // test 5: 2xuint16 vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_u16, 2, 1);
        try check(&[_]u8{}, b, &i); // align to 4byte
        try b.prepend(u16, 0xABCD);
        try check(&[_]u8{ 0xCD, 0xAB }, b, &i);
        try b.prepend(u16, 0xDCBA);
        try check(&[_]u8{ 0xBA, 0xDC, 0xCD, 0xAB }, b, &i);
        _ = b.endVector(2);
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
            6, 0, 0, 0, // offset for start of vtable (int32)
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
            4, 0, 0, 0, // offset for start of vtable (int32)
        }, b, &i);
    }
    { // test 10: vtable with one int16
        var b = Builder.init(alloc);
        defer b.deinitAll();

        try b.startObject(1);
        try b.prependSlot(i16, 0, 0x789A, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0, // end of object from here
            6, 0, // offset to value
            6, 0, 0, 0, // offset for start of vtable (int32)
            0,    0, // padding to 4 bytes
            0x9A, 0x78,
        }, b, &i);
    }
    { // test 11: vtable with two int16
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
            8, 0, 0, 0, // offset for start of vtable (int32)
            0x9A, 0x78, // value 1
            0x56, 0x34, // value 0
        }, b, &i);
    }
    { // test 12: vtable with int16 and bool
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
            8, 0, 0, 0, // offset for start of vtable (int32)
            0, // padding
            1, // value 1
            0x56, 0x34, // value 0
        }, b, &i);
    }
    { // test 12: vtable with empty vector
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_byte, 0, 1);
        const vecend = b.endVector(0);
        _ = try b.startObject(1);
        try b.prependSlotUOff(0, vecend, 0);

        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0,
            4, 0, // offset to vector offset
            6, 0, 0, 0, // offset for start of vtable (int32)
            4, 0, 0, 0,
            0, 0, 0, 0, // length of vector (not in struct)
        }, b, &i);
    }
    { // test 12b: vtable with empty vector of byte and some scalars
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_byte, 0, 1);
        const vecend = b.endVector(0);
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
    { // test 13: vtable with 1 int16 and 2-vector of int16
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_i16, 2, 1);
        try b.prepend(i16, 0x1234);
        try b.prepend(i16, 0x5678);
        const vecend = b.endVector(2);
        _ = try b.startObject(2);
        try b.prependSlotUOff(1, vecend, 0);
        try b.prependSlot(i16, 0, 55, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            8, 0, // vtable bytes
            12, 0, // length of object
            6, 0, // start of value 0 from end of vtable
            8, 0, // start of value 1 from end of buffer
            8, 0, 0, 0, // offset for start of vtable (int32)
            0, 0, // padding
            55, 0, // value 0
            4, 0, 0, 0, // vector position from here
            2, 0, 0, 0, // length of vector (uint32)
            0x78, 0x56, // vector value 1
            0x34, 0x12, // vector value 0
        }, b, &i);
    }
    { // test 14: vtable with 1 struct of 1 int8, 1 int16, 1 int32
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
        b.prependSlotStruct(0, structStart, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            16, 0, // end of object from here
            4, 0, // start of struct from here
            6, 0, 0, 0, // offset for start of vtable (int32)
            0x78, 0x56, 0x34, 0x12, // value 2
            0, 0, // padding
            0x34, 0x12, // value 1
            0, 0, 0, // padding
            55, // value 0
        }, b, &i);
    }
    { // test 15: vtable with 1 vector of 2 struct of 2 int8
        var b = Builder.init(alloc);
        defer b.deinitAll();

        _ = try b.startVector(fb.Builder.size_i8 * 2, 2, 1);
        try b.prepend(i8, 33);
        try b.prepend(i8, 44);
        try b.prepend(i8, 55);
        try b.prepend(i8, 66);
        const vecend = b.endVector(2);
        _ = try b.startObject(1);
        try b.prependSlotUOff(0, vecend, 0);
        _ = try b.endObject();
        try check(&[_]u8{
            6, 0, // vtable bytes
            8, 0,
            4, 0, // offset of vector offset
            6, 0, 0, 0, // offset for start of vtable (int32)
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
            8, 0, 0, 0, // offset for start of vtable (int32)
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
            10, 0, 0, 0, // offset for start of vtable (int32)
            0, // padding
            77, // value 2
            66, // value 1
            55, // value 0
            12, 0, 0, 0, // root of table: points to object
            8, 0, // vtable bytes
            8, 0, // size of object
            7, 0, // start of value 0
            6, 0, // start of value 1
            8, 0, 0, 0, // offset for start of vtable (int32)
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
            try testing.expect(tb.mutate(u32, calcUOffsetT(calcVOffsetT(12), tb), 24));
            try testing.expect(tb.mutate(u16, calcUOffsetT(calcVOffsetT(13), tb), 26));
            try testing.expect(tb.mutate(i32, calcUOffsetT(calcVOffsetT(14), tb), 28));
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
    const vec3_bytes = b.finishedBytes();
    const vec3 = fb.GetRootAs(vec3_bytes, 0, Vec3);
    try testing.expect(mem.eql(u8, vec3_bytes, vec3.Table().bytes));
    b.deinit();
    alloc.free(vec3_bytes);

    // test table accessor
    b = Builder.init(alloc);
    defer b.deinit();
    const str = try b.createString("MyStat");
    try Stat.Start(&b);
    try Stat.AddId(&b, str);
    try Stat.AddVal(&b, 12345678);
    try Stat.AddCount(&b, 12345);
    const pos2 = try Stat.End(&b);
    _ = try b.finish(pos2);
    const stat_bytes = b.finishedBytes();
    const stat = Stat.GetRootAs(stat_bytes, 0);
    try testing.expect(mem.eql(u8, stat_bytes, stat.Table().bytes));
    alloc.free(stat_bytes);
}

/// checks that the given buffer is evaluated correctly
/// as the example Monster.
fn checkReadBuffer(
    alloc: mem.Allocator,
    buf: []u8,
    offset: u32,
    sizePrefix: bool,
    comptime fail: Fail,
) !void {
    _ = alloc;
    // try the two ways of generating a monster
    const mons = if (sizePrefix) {
        // example.GetSizePrefixedRootAsMonster(buf, offset),
        // flatbuffers.GetSizePrefixedRootAs(buf, offset, monster2),
        fail("TODO: checkReadBuffer() sizePrefix=true", .{});
        return error.TODO;
    } else [_]Monster{
        Monster.GetRootAs(buf, offset),
        fb.GetRootAs(buf, offset, Monster),
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
            fail("Pox.X() != 1.0. i = {}", .{i});
            return e;
        };
        testing.expectApproxEqAbs(@as(f32, 2.0), vec.Y(), std.math.f32_epsilon) catch |e| {
            fail("Pox.Y() != 2.0. i = {}", .{i});
            return e;
        };
        testing.expectApproxEqAbs(@as(f32, 3.0), vec.Z(), std.math.f32_epsilon) catch |e| {
            fail("Pox.Z() != 3.0. i = {}", .{i});
            return e;
        };

        testing.expectApproxEqAbs(@as(f64, 3.0), vec.Test1(), std.math.f32_epsilon) catch |e| {
            fail("Pox.Test1() != 3.0. i = {}", .{i});
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
    comptime fail: Fail,
) !void {
    _ = fail;

    // make a copy to mutate
    var buf = try alloc.dupe(u8, org);
    defer alloc.free(buf);

    // load monster data from the buffer
    var monster = if (sizePrefix)
        // monster = example.GetSizePrefixedRootAsMonster(buf, offset)
        fb.common.todo("sizePrefix=true, GetSizePrefixedRootAsMonster", .{})
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
        // monster = example.GetSizePrefixedRootAsMonster(buf, offset)
        fb.common.todo("sizePrefix=true, GetSizePrefixedRootAsMonster", .{})
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
        // monster = example.GetSizePrefixedRootAsMonster(buf, offset)
        fb.common.todo("sizePrefix=true, GetSizePrefixedRootAsMonster", .{})
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
    comptime fail: Fail,
) !void {
    var monster = if (sizePrefix)
        // monster = example.GetSizePrefixedRootAsMonster(buf, offset).UnPack()
        return fail("TODO checkObjectAPI() sizePrefix=true", .{})
    else
        try MonsterT.unpack(Monster.GetRootAs(buf, offset), .{ .allocator = alloc });

    defer monster.deinit(alloc);

    try std.testing.expectEqual(@as(i16, 80), monster.hp);

    // default
    try std.testing.expectEqual(@as(i16, 150), monster.mana);

    if (monster.@"test" == .Monster) monster.@"test".Monster.?.nan_default = 0.0;
    if (monster.enemy) |x| x.nan_default = 0.0;
    monster.nan_default = 0.0;

    var builder = fb.Builder.init(alloc);
    defer builder.deinitAll();

    try builder.finish(try monster.pack(&builder, .{ .allocator = alloc }));
    const m = Monster.GetRootAs(builder.finishedBytes(), 0);
    var monster2 = try MonsterT.unpack(m, .{ .allocator = alloc });
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

        _ = b1.endVector(@intCast(u32, size));
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

        break :blk try alloc.dupe(u8, builder.finishedBytes());
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

        break :blk try alloc.dupe(u8, builder.finishedBytes());
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
    try builder.finish(try food.pack(&builder, .{ .allocator = alloc }));

    // Receive order
    const received_food = Food.GetRootAs(builder.finishedBytes(), 0);
    const received_pizza = try PizzaT.unpack(received_food.Pizza_().?, .{ .allocator = alloc });

    try expectEqualDeep(ordered_pizza, received_pizza);
}

const talloc = testing.allocator;
test "all" {
    // Verify that the Go FlatBuffers runtime library generates the
    // expected bytes (does not use any schema):
    try checkByteLayout(talloc);
    try checkMutateMethods(talloc);

    // Verify that GetRootAs works for non-root tables
    try checkGetRootAsForNonRootTable(talloc);
    try checkTableAccessors(talloc);

    // Verify that using the generated code builds a buffer without
    // returning errors:
    const gen_off = try checkGeneratedBuild(talloc, false, std.log.err);
    const generated = gen_off[0];
    defer talloc.free(generated);
    const off = gen_off[1];

    // Verify that the buffer generated by zig code is readable by the
    // generated code
    try checkReadBuffer(talloc, generated, off, false, std.log.err);
    try checkMutateBuffer(talloc, generated, off, false, std.log.err);
    try checkObjectAPI(talloc, generated, off, false, std.log.err);

    // Verify that the buffer generated by C++ code is readable by the
    // generated zig code:
    const monster_data_cpp = try std.fs.cwd().readFileAlloc(
        talloc,
        "examples/monsterdata_test.mon",
        std.math.maxInt(u32),
    );
    defer talloc.free(monster_data_cpp);

    try checkReadBuffer(talloc, monster_data_cpp, 0, false, std.log.err);
    try checkMutateBuffer(talloc, monster_data_cpp, 0, false, std.log.err);
    try checkObjectAPI(talloc, monster_data_cpp, 0, false, std.log.err);

    // Verify that vtables are deduplicated when written:
    try checkVtableDeduplication(talloc);

    // Verify the enum names
    try checkEnumNamesAndValues();

    // Check Builder.CreateByteVector
    try checkCreateByteVector(talloc);

    // Check a parent namespace import
    try checkParentNamespace(talloc);

    // Check a no namespace import
    try checkNoNamespaceImport(talloc);
}
