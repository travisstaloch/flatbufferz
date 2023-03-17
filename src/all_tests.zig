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
const Fail = fn (comptime []const u8, anytype) void;

// build an example Monster. returns (buf,offset)
fn checkGeneratedBuild(
    alloc: mem.Allocator,
    sizePrefix: bool,
    comptime fail: Fail,
) !struct { []const u8, u32 } {
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

/// checks that the given buffer is evaluated correctly
/// as the example Monster.
fn checkReadBuffer(
    alloc: mem.Allocator,
    buf: []const u8,
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
fn checkObjectAPI(
    alloc: mem.Allocator,
    buf: []const u8,
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
    defer builder.deinit();
    try builder.finish(try monster.pack(&builder, .{ .allocator = alloc }));
    const m = Monster.GetRootAs(builder.finishedBytes(), 0);
    var monster2 = try MonsterT.unpack(m, .{ .allocator = alloc });
    defer monster2.deinit(alloc);
    // TODO use std.testing.expectEqualDeep() once
    // https://github.com/ziglang/zig/pull/14981 is merged
    try @import("testing.zig").expectEqualDeep(monster, monster2);
}

const talloc = testing.allocator;
test "Object API" {
    // Verify that using the generated code builds a buffer without
    // returning errors:
    const gen_off = try checkGeneratedBuild(talloc, false, std.log.err);
    const generated = gen_off[0];
    const off = gen_off[1];

    // Verify that the buffer generated by Go code is readable by the
    // generated code
    // CheckReadBuffer(generated, off, false, t.Fatalf)
    try checkReadBuffer(talloc, generated, off, false, std.log.err);
    // CheckMutateBuffer(generated, off, false, t.Fatalf)
    try checkObjectAPI(talloc, generated, off, false, std.log.err);
}
