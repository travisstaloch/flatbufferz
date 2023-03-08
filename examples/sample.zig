//! this file will eventually be replaced by generated code. but for now
//! its hand-written in order to 'bootstrap' the project

const fb = @import("flatbufferz");
const Builder = fb.Builder;
const Table = fb.Table;
const sample = @This();

pub fn WeaponStart(builder: *Builder) !void {
    try builder.startObject(2);
}
pub fn WeaponAddName(builder: *Builder, name: u32) !void {
    try builder.prependSlotUOff(0, name, 0);
}
pub fn WeaponAddDamage(builder: *Builder, damage: i16) !void {
    try builder.prependSlot(i16, 1, damage, 0);
}
pub fn WeaponEnd(builder: *Builder) !u32 {
    return builder.endObject();
}

pub fn MonsterStartInventoryVector(builder: *Builder, numElems: i32) !u32 {
    return builder.startVector(1, numElems, 1);
}

pub fn MonsterStartWeaponsVector(builder: *Builder, numElems: i32) !u32 {
    return builder.startVector(4, numElems, 4);
}

pub fn CreateVec3(builder: *Builder, x: f32, y: f32, z: f32) !u32 {
    try builder.prep(4, 12);
    try builder.prepend(f32, z);
    try builder.prepend(f32, y);
    try builder.prepend(f32, x);
    return builder.offset();
}

pub fn MonsterStart(builder: *Builder) !void {
    try builder.startObject(11);
}

pub fn MonsterAddPos(builder: *Builder, pos: u32) void {
    builder.prependSlotStruct(0, pos, 0);
}

pub fn MonsterAddHp(builder: *Builder, hp: i16) !void {
    try builder.prependSlot(i16, 2, hp, 100);
}
pub fn MonsterAddName(builder: *Builder, name: u32) !void {
    try builder.prependSlotUOff(3, name, 0);
}
pub fn MonsterAddInventory(builder: *Builder, inventory: u32) !void {
    try builder.prependSlotUOff(5, inventory, 0);
}
const Color = i8;
pub const ColorRed: Color = 0;
pub const ColorGreen: Color = 1;
pub const ColorBlue: Color = 2;

pub fn MonsterAddColor(builder: *Builder, color: Color) !void {
    try builder.prependSlot(Color, 6, color, 2);
}
pub fn MonsterAddWeapons(builder: *Builder, weapons: u32) !void {
    try builder.prependSlotUOff(7, weapons, 0);
}
const Equipment = u8;
pub const EquipmentNONE: Equipment = 0;
pub const EquipmentWeapon: Equipment = 1;

pub fn MonsterAddEquippedType(builder: *Builder, equippedType: Equipment) !void {
    try builder.prependSlot(u8, 8, equippedType, 0);
}
pub fn MonsterAddEquipped(builder: *Builder, equipped: u32) !void {
    try builder.prependSlotUOff(9, equipped, 0);
}

pub fn MonsterEnd(builder: *Builder) !u32 {
    return builder.endObject();
}

pub const Vec3 = struct {
    _tab: fb.Struct,

    pub fn init(buf: []const u8, i: u32) Vec3 {
        return .{ ._tab = fb.Struct.init(buf, i) };
    }

    pub fn X(v: Vec3) f32 {
        return v._tab._tab.read(f32, v._tab._tab.pos + 0);
    }
    pub fn Y(v: Vec3) f32 {
        return v._tab._tab.read(f32, v._tab._tab.pos + 4);
    }
    pub fn Z(v: Vec3) f32 {
        return v._tab._tab.read(f32, v._tab._tab.pos + 8);
    }
};

pub const Weapon = struct {
    _tab: Table,

    pub const init = Table.Init(Weapon);
    pub const Name = Table.ReadByteVec(Weapon, 4, null);
    pub const Damage = Table.ReadWithDefault(Weapon, u16, 6, .required);
};

pub const Monster = struct {
    _tab: Table,

    pub const init = Table.Init(Monster);
    pub const Pos = Table.ReadStruct(Monster, Vec3, 4);
    pub const Mana = Table.ReadWithDefault(Monster, u16, 6, .{ .optional = 150 });
    pub const Hp = Table.ReadWithDefault(Monster, u16, 8, .{ .optional = 100 });
    pub const Name = Table.ReadByteVec(Monster, 10, null);
    pub const InventoryLen = Table.VectorLen(Monster, 14);
    pub const Inventory = Table.VectorAt(Monster, u8, 14, 0);
    pub const Color = Table.ReadWithDefault(Monster, sample.Color, 16, .{ .optional = 2 });
    pub const WeaponsLen = Table.VectorLen(Monster, 18);
    pub const Weapons = Table.VectorAt(Monster, Weapon, 18, null);
    pub const EquippedType = Table.ReadWithDefault(Monster, u8, 20, .{ .optional = 0 });

    pub fn Equipped(rcv: Monster) ?Table {
        const o = rcv._tab.offset(22);
        if (o != 0) {
            return rcv._tab.union_(o);
        }
        return null;
    }
};

pub fn GetRootAsMonster(buf: []const u8, offset: u32) Monster {
    const n = fb.encode.read(u32, buf[offset..]);
    return Monster.init(buf, n + offset);
}
