//! this file will eventually be replaced by generated code. but for now
//! its hand-written in order to 'bootstrap' the project

const fb = @import("flatbuffers");
const Builder = fb.Builder;
const sample = @This();

pub fn WeaponStart(builder: *Builder) !void {
    try builder.startObject(2);
}
pub fn WeaponAddName(builder: *Builder, name: u32) !void {
    try builder.prependUOffSlot(0, name, 0);
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
    builder.prependStructSlot(0, pos, 0);
}

pub fn MonsterAddHp(builder: *Builder, hp: i16) !void {
    try builder.prependSlot(i16, 2, hp, 100);
}
pub fn MonsterAddName(builder: *Builder, name: u32) !void {
    try builder.prependUOffSlot(3, name, 0);
}
pub fn MonsterAddInventory(builder: *Builder, inventory: u32) !void {
    try builder.prependUOffSlot(5, inventory, 0);
}
const Color = i8;
pub const ColorRed: Color = 0;
pub const ColorGreen: Color = 1;
pub const ColorBlue: Color = 2;

pub fn MonsterAddColor(builder: *Builder, color: Color) !void {
    try builder.prependSlot(Color, 6, color, 2);
}
pub fn MonsterAddWeapons(builder: *Builder, weapons: u32) !void {
    try builder.prependUOffSlot(7, weapons, 0);
}
const Equipment = u8;
pub const EquipmentNONE: Equipment = 0;
pub const EquipmentWeapon: Equipment = 1;

pub fn MonsterAddEquippedType(builder: *Builder, equippedType: Equipment) !void {
    try builder.prependSlot(u8, 8, equippedType, 0);
}
pub fn MonsterAddEquipped(builder: *Builder, equipped: u32) !void {
    try builder.prependUOffSlot(9, equipped, 0);
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
    _tab: fb.Table,

    pub fn init(buf: []const u8, i: u32) Weapon {
        return .{ ._tab = fb.Table.init(buf, i) };
    }

    pub fn Name(w: Weapon) []const u8 {
        return w._tab.readByteVectorWithDefault(4, "");
    }
    pub fn Damage(w: Weapon) u16 {
        return w._tab.read(u16, w._tab.pos + 6);
    }
};

pub const Monster = struct {
    _tab: fb.Table,

    pub fn init(buf: []const u8, i: u32) Monster {
        return .{ ._tab = fb.Table.init(buf, i) };
    }
    pub fn Mana(m: Monster) u16 {
        return m._tab.readWithDefault(u16, 6, 150);
    }
    pub fn Hp(m: Monster) u16 {
        return m._tab.readWithDefault(u16, 8, 100);
    }
    pub fn Color(m: Monster) sample.Color {
        return m._tab.readWithDefault(sample.Color, 16, 2);
    }
    pub fn Name(m: Monster) []const u8 {
        return m._tab.readByteVectorWithDefault(10, "");
    }
    pub fn Pos(m: Monster) ?Vec3 {
        const o = m._tab.offset(4);
        if (o != 0) {
            const x = o + m._tab.pos;
            return Vec3.init(m._tab.bytes, x);
        }
        return null;
    }
    pub fn Inventory(m: Monster, j: usize) u8 {
        const o = m._tab.offset(14);
        if (o != 0) {
            const a = m._tab.vector(o);
            return m._tab.read(u8, a + @intCast(u32, j) * 1);
        }
        return 0;
    }
    pub fn InventoryLength(m: Monster) u32 {
        return m._tab.readVectorLen(14);
    }
    pub fn WeaponsLength(m: Monster) u32 {
        return m._tab.readVectorLen(18);
    }
    pub fn Weapons(m: Monster, j: usize) ?Weapon {
        const o = m._tab.offset(18);
        if (o != 0) {
            var x = m._tab.vector(o);
            x += @intCast(u32, j) * 4;
            x = m._tab.indirect(x);
            return Weapon.init(m._tab.bytes, x);
        }
        return null;
    }
    pub fn EquippedType(m: Monster) u8 {
        return m._tab.readWithDefault(u8, 20, 0);
    }
    pub fn Equipped(rcv: Monster) ?fb.Table {
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
