//!
//! a port of https://github.com/google/flatbuffers/blob/master/tests/go_test.go
//!

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const fb = @import("flatbufferz");
const Builder = fb.Builder;
const Monster = @import("generated").MyGame_Example_Monster.Monster;
const Test = @import("generated").MyGame_Example_Test.Test;
const Vec3 = @import("generated").MyGame_Example_Vec3.Vec3;
const Color = @import("generated").MyGame_Example_Color.Color;

// build an example Monster. returns (buf,offset)
fn checkGeneratedBuild(alloc: mem.Allocator, sizePrefix: bool, fail: *const fn (comptime []const u8, anytype) void) !struct { []const u8, u32 } {
    _ = fail;
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

    const pos = try Vec3.Create(&b, 3.0, .Green, 5, 6, 1.0, 2.0, 3.0);
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
        b.FinishSizePrefixed(mon);
    } else {
        try b.finish(mon);
    }

    return .{ try b.bytes.toOwnedSlice(b.alloc), b.head };
}

const talloc = testing.allocator;
test "Object API" {
    // Verify that using the generated code builds a buffer without
    // returning errors:
    testing.log_level = .info;
    const bytes_off = try checkGeneratedBuild(talloc, false, std.log.err);
    const bytes = bytes_off[0];
    defer talloc.free(bytes);
}
