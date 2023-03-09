const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const builtin = @import("builtin");
const fb = @import("flatbufferz");
const Builder = fb.Builder;
// const sample = @import("sample.zig");
const Monster = @import("../gen/Monster.fb.zig").Monster;
const Weapon = @import("../gen/Weapon.fb.zig").Weapon;
const Vec3 = @import("../gen/Vec3.fb.zig").Vec3;
const Color = @import("../gen/Color.fb.zig").Color;
const Equipment = @import("../gen/Equipment.fb.zig").Equipment;

pub const std_options = struct {
    pub const log_level = std.meta.stringToEnum(std.log.Level, @tagName(@import("build_options").log_level)).?;
};

// test sample {
//     try main();
// }

/// Example of how to use Flatbuffers to create and read binary buffers.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    var builder = Builder.init(alloc);

    // Create some weapons for our Monster ("Sword" and "Axe").
    var weaponOne = try builder.createString("Sword");
    var weaponTwo = try builder.createString("Axe");

    try Weapon.Start(&builder);
    try Weapon.AddName(&builder, weaponOne);
    try Weapon.AddDamage(&builder, 3);
    const sword = try Weapon.End(&builder);
    try Weapon.Start(&builder);
    try Weapon.AddName(&builder, weaponTwo);
    try Weapon.AddDamage(&builder, 5);
    const axe = try Weapon.End(&builder);

    // Serialize the FlatBuffer data.
    const name = try builder.createString("Orc");

    _ = try Monster.StartInventoryVector(&builder, 10);
    for (0..10) |i| try builder.prepend(u8, @intCast(u8, 9 - i));
    const inv = builder.endVector(10);
    _ = try Monster.StartWeaponsVector(&builder, 2);
    // Note: Since we prepend the weapons, prepend in reverse order.
    try builder.prependUOff(axe);
    try builder.prependUOff(sword);
    const weapons = builder.endVector(2);
    const pos = try Vec3.Create(&builder, 1.0, 2.0, 3.0);
    try Monster.Start(&builder);
    Monster.AddPos(&builder, pos);
    try Monster.AddHp(&builder, 300);
    try Monster.AddName(&builder, name);
    try Monster.AddInventory(&builder, inv);
    try Monster.AddColor_(&builder, .Red);
    try Monster.AddWeapons(&builder, weapons);
    try Monster.AddEquippedType(&builder, .weapon);
    try Monster.AddEquipped(&builder, axe);
    const orc = try Monster.End(&builder);
    try builder.finish(orc);

    // We now have a FlatBuffer that we could store on disk or send over a network.
    // ...Saving to file or sending over a network code goes here...
    // Instead, we are going to access this buffer right away (as if we just received it).

    const buf = builder.finishedBytes();

    // Note: We use `0` for the offset here, since we got the data using the
    // `builder.FinishedBytes()` method. This simulates the data you would store/receive in your
    // FlatBuffer. If you wanted to read from the `builder.Bytes` directly, you would need to
    // pass in the offset of `builder.head`, as the builder actually constructs the buffer
    // backwards.
    const monster = Monster.GetRootAs(buf, 0);
    try testing.expectEqual(@as(i16, 150), monster.Mana());
    try testing.expectEqual(@as(i16, 300), monster.Hp());
    try testing.expectEqualStrings("Orc", monster.Name());
    try testing.expectEqual(Color.Red, monster.Color_());
    try testing.expectApproxEqAbs(@as(f32, 1.0), monster.Pos().?.X(), std.math.f32_epsilon);
    try testing.expectApproxEqAbs(@as(f32, 2.0), monster.Pos().?.Y(), std.math.f32_epsilon);
    try testing.expectApproxEqAbs(@as(f32, 3.0), monster.Pos().?.Z(), std.math.f32_epsilon);

    // For vectors, like `Inventory`, they have a method suffixed with 'Length' that can be used
    // to query the length of the vector. You can index the vector by passing an index value
    // into the accessor.
    for (0..monster.InventoryLen()) |i|
        try testing.expectEqual(@intCast(u8, i), monster.Inventory(i));

    const expected_weapon_names = [_][]const u8{ "Sword", "Axe" };
    const expected_weapon_damages = [_]i16{ 3, 5 };

    for (0..monster.WeaponsLen()) |i| {
        if (monster.Weapons(i)) |weapon| {
            try testing.expectEqualStrings(expected_weapon_names[i], weapon.Name());
            try testing.expectEqual(expected_weapon_damages[i], weapon.Damage());
        }
    }

    // For FlatBuffer `union`s, you can get the type of the union, as well as the union
    // data itself.
    try testing.expectEqual(Equipment.Tag.weapon, monster.EquippedType());
    if (monster.Equipped()) |union_table| {
        // An example of how you can appropriately convert the table depending on the
        // FlatBuffer `union` type. You could add `else if` and `else` clauses to handle
        // other FlatBuffer `union` types for this field. (Similarly, this could be
        // done in a switch statement.)
        if (monster.EquippedType() == .weapon) {
            const w = Weapon.init(union_table.bytes, union_table.pos);
            try testing.expectEqualStrings("Axe", w.Name());
            try testing.expectEqual(@as(i16, 5), w.Damage());
        }
    }

    if (!builtin.is_test)
        std.debug.print("The FlatBuffer was successfully created and verified!\n", .{});
}
