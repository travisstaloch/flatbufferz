//!
//! A port of https://github.com/google/flatbuffers/blob/master/go/builder.go
//!
//! Builder is a state machine for creating FlatBuffer objects.
//! Use a Builder to construct object(s) starting from leaf nodes.
//!
//! A Builder constructs byte buffers in a last-first manner for simplicity and
//! performance.

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const encode = @import("encode.zig");
const vtable_metadata_fields = encode.vtable_metadata_fields;
const read = encode.read;
const write = encode.write;
const common = @import("common.zig");
const todo = common.todo;
const Builder = @This();

alloc: mem.Allocator,
bytes: std.ArrayList(u8) = .{},
minalign: u32,
vtable: std.ArrayList(u32) = .{},
object_end: u32,
vtables: std.ArrayList(u32) = .{},
head: u32,
nested: bool,
finished: bool,
shared_strings: std.StringHashMapUnmanaged(u32) = .{},

pub const Fid = [4]u8;
pub const file_identifier_len: i32 = @typeInfo(Fid).array.len;
pub const size_prefix_length = 4;

pub const size_u8 = @sizeOf(u8);
pub const size_byte = size_u8;
pub const size_u16 = @sizeOf(u16);
pub const size_u32 = @sizeOf(u32);
pub const size_u64 = @sizeOf(u64);
pub const size_i8 = @sizeOf(i8);
pub const size_i16 = @sizeOf(i16);
pub const size_i32 = @sizeOf(i32);
pub const size_i64 = @sizeOf(i64);
pub const size_f32 = @sizeOf(f32);
pub const size_f64 = @sizeOf(f64);
pub const size_bool = @sizeOf(bool);

/// initializes an empty Builder
pub fn init(alloc: mem.Allocator) Builder {
    return .{
        .alloc = alloc,
        .minalign = 1,
        .object_end = 0,
        .head = 0,
        .nested = false,
        .finished = false,
    };
}

/// initializes an empty Builder with `bytes` pre-allocated to `capacity`
pub fn initCapacity(alloc: mem.Allocator, capacity: usize) !Builder {
    return .{
        .alloc = alloc,
        .minalign = 1,
        .object_end = 0,
        .head = 0,
        .nested = false,
        .finished = false,
        .bytes = try std.ArrayList(u8).initCapacity(alloc, capacity),
    };
}

/// deinit `shared_strings`, `vtable`, `vtables`.
/// does not deinit `bytes`.
pub fn deinit(b: *Builder) void {
    b.shared_strings.deinit(b.alloc);
    b.vtable.deinit(b.alloc);
    b.vtables.deinit(b.alloc);
}

/// deinit `shared_strings`, `vtable`, `vtables` and `bytes`.
pub fn deinitAll(b: *Builder) void {
    b.shared_strings.deinit(b.alloc);
    b.vtable.deinit(b.alloc);
    b.vtables.deinit(b.alloc);
    b.bytes.deinit(b.alloc);
}

fn debug(b: Builder, comptime fmt: []const u8, args: anytype) void {
    // std.log.debug(
    //     fmt ++ "bytes={any}, minalign={}, vtable={any}, bject_end=={}, vtables={any}, head={}, nested={}, finished={}",
    //     args ++ .{ b.bytes.items, b.minalign, b.vtable.items, b.object_end, b.vtables.items, b.head, b.nested, b.finished },
    // );
    _ = b;
    std.log.debug(fmt, args);
}

/// Reset truncates the underlying Builder buffer, facilitating alloc-free
/// reuse of a Builder. It also resets bookkeeping data.
pub fn reset(b: *Builder) void {
    b.bytes.expandToCapacity();
    b.vtables.items.len = 0;
    b.vtable.items.len = 0;
    b.shared_strings.clearRetainingCapacity();
    b.head = @intCast(b.bytes.items.len);
    b.minalign = 1;
    b.nested = false;
    b.finished = false;
}

/// returns a pointer to the written data in the byte buffer.
/// errors if the builder is not in a finished state (which is caused by calling
pub fn finishedBytes(b: *Builder) ![]u8 {
    try b.checkFinished();
    return b.bytes.items[b.head..];
}

/// initializes bookkeeping for writing a new object.
pub fn startObject(b: *Builder, numfields: u32) !void {
    try b.checkNotNested();
    b.nested = true;
    try b.vtable.ensureTotalCapacity(b.alloc, numfields);
    b.vtable.items.len = numfields;
    @memset(b.vtable.items, 0);
    b.object_end = b.offset();
}

/// serializes the vtable for the current object, if applicable.
///
/// Before writing out the vtable, this checks pre-existing vtables for equality
/// to this one. If an equal vtable is found, point the object to the existing
/// vtable and return.
///
/// Because vtable values are sensitive to alignment of object data, not all
/// logically-equal vtables will be deduplicated.
///
/// A vtable has the following format:
///   <u16: size of the vtable in bytes, including this value>
///   <u16: size of the object in bytes, including the vtable offset>
///   <u16: offset for a field> * N, where N is the number of fields in
///          the schema for this type. Includes deprecated fields.
/// Thus, a vtable is made of 2 + N elements, each size_u16 bytes wide.
///
/// An object has the following format:
///   <soff: offset to this object's vtable (may be negative)>
///   <byte: data>+
pub fn writeVtable(b: *Builder) !u32 {
    // Prepend a zero scalar to the object. Later in this function we'll
    // write an offset here that points to the object's vtable:
    try b.prependSOff(0);

    const object_offset = b.offset();
    var existing_vtable = @as(u32, 0);

    // Trim vtable of trailing zeroes.
    {
        var i = @as(isize, @bitCast(b.vtable.items.len)) - 1;
        while (i >= 0 and b.vtable.items[@as(usize, @bitCast(i))] == 0) : (i -= 1) {}
        b.vtable.items.len = @as(usize, @bitCast(i + 1));
    }
    // Search backwards through existing vtables, because similar vtables
    // are likely to have been recently appended. See
    // BenchmarkVtableDeduplication for a case in which this heuristic
    // saves about 30% of the time used in writing objects with duplicate
    // tables.
    {
        var i = @as(isize, @bitCast(b.vtables.items.len)) - 1;
        while (i >= 0) : (i -= 1) {
            // Find the other vtable, which is associated with `i`:
            const vt2_offset = b.vtables.items[@bitCast(i)];
            const vt2_start = b.bytes.items.len - vt2_offset;
            const vt2_len = read(u16, b.bytes.items[vt2_start..]);

            const metadata = vtable_metadata_fields * size_u16;
            const vt2_end = vt2_start + vt2_len;
            const vt2 = b.bytes.items[vt2_start + metadata .. vt2_end];

            // Compare the other vtable to the one under consideration.
            // If they are equal, store the offset and break:
            if (vtableEqual(b.vtable.items, object_offset, vt2)) {
                existing_vtable = vt2_offset;
                break;
            }
        }
    }

    if (existing_vtable == 0) {
        // Did not find a vtable, so write this one to the buffer.

        // Write out the current vtable in reverse , because
        // serialization occurs in last-first order:
        {
            var i = @as(isize, @bitCast(b.vtable.items.len)) - 1;
            while (i >= 0) : (i -= 1) {
                var off: u32 = 0;
                const ii: usize = @bitCast(i);
                if (b.vtable.items[ii] != 0) {
                    // Forward reference to field;
                    // use 32bit number to assert no overflow:
                    off = object_offset - b.vtable.items[ii];
                }

                try b.prepend(u16, @as(u16, @intCast(off)));
            }
        }
        // The two metadata fields are written last.

        // First, store the object bytesize:
        const object_size = object_offset - b.object_end;
        try b.prepend(u16, @as(u16, @intCast(object_size)));

        // Second, store the vtable bytesize:
        const v_bytes = (b.vtable.items.len + vtable_metadata_fields) * size_u16;
        try b.prepend(u16, @as(u16, @intCast(v_bytes)));

        // Next, write the offset to the new vtable in the
        // already-allocated soff at the beginning of this object:
        const object_start = b.bytes.items.len - object_offset;
        write(i32, b.bytes.items[object_start..], @as(i32, @intCast(b.offset() -
            object_offset)));

        // Finally, store this vtable in memory for future
        // deduplication:
        try b.vtables.append(b.alloc, b.offset());
    } else {
        // Found a duplicate vtable.

        const object_start = @as(u32, @intCast(b.bytes.items.len)) - object_offset;
        b.head = object_start;

        // Write the offset to the found vtable in the
        // already-allocated soff at the beginning of this object:
        write(i32, b.bytes.items[b.head..], @as(i32, @bitCast(existing_vtable)) -
            @as(i32, @bitCast(object_offset)));
    }

    b.vtable.items.len = 0;
    return object_offset;
}

/// writes data necessary to finish object construction.
pub fn endObject(b: *Builder) !u32 {
    try b.checkNested();
    const n = try b.writeVtable();
    b.nested = false;
    return n;
}

fn err(
    comptime fmt: []const u8,
    args: anytype,
    e: common.BuilderError,
) common.BuilderError {
    std.log.err(fmt, args);
    return e;
}

/// Doubles the size of the b.bytes, and copies the old data towards the
/// end of the new byteslice (since we build the buffer backwards).
pub fn growByteBuffer(b: *Builder) !void {
    if ((b.bytes.items.len & 0xC0000000) != 0)
        return err(
            "cannot grow buffer beyond 2 gigabytes",
            .{},
            error.OutOfMemory,
        );

    var new_len = b.bytes.items.len * 2;
    if (new_len == 0) new_len = 32;

    if (b.bytes.capacity >= new_len)
        b.bytes.items.len = new_len
    else {
        try b.bytes.ensureTotalCapacity(b.alloc, new_len);
        b.bytes.items.len = new_len;
    }

    const middle = new_len / 2;
    std.mem.copyForwards(u8, b.bytes.items[middle..], b.bytes.items[0..middle]);
}

/// returns offset relative to the end of the buffer.
pub fn offset(b: *Builder) u32 {
    return @as(u32, @intCast(b.bytes.items.len)) - b.head;
}

/// places zeros at the current offset
pub fn pad(b: *Builder, n: u32) void {
    for (0..n) |_| b.place(u8, 0);
}

/// prepares to write an element of `size` after `additional_bytes`
/// have been written, e.g. if you write a []const u8, you need to align such
/// the int length field is aligned to size_i32, and the []const u8 data follows it
/// directly.
/// If all you need to do is align, `additional_bytes` will be 0.
pub fn prep(b: *Builder, size: i32, additional_bytes: i32) !void {
    // Track the biggest thing we've ever aligned to.
    if (size > b.minalign) b.minalign = @bitCast(size);

    // Find the amount of alignment needed such that `size` is properly
    // aligned after `additional_bytes`:
    var align_size = (~(@as(i64, @bitCast(b.bytes.items.len)) - @as(i32, @bitCast(b.head)) + additional_bytes) + 1);
    align_size &= size - 1;

    b.debug("prep() 1 b.head={} align_size={} additional_bytes={} size={}", .{ b.head, align_size, additional_bytes, size });
    // Reallocate the buffer if needed:
    while (b.head <= align_size + size + additional_bytes) {
        const old_buf_size = b.bytes.items.len;
        try b.growByteBuffer();
        b.head += @intCast(b.bytes.items.len - old_buf_size);
    }
    b.pad(@intCast(align_size));
    b.debug("prep() b.head={} bytes.len={}", .{ b.head, b.bytes.items.len });
}

/// prepends a i32, relative to where it will be written.
pub fn prependSOff(b: *Builder, off: i32) !void {
    try b.prep(size_i32, 0); // Ensure alignment is already done.
    if (off > b.offset())
        return err("unreachable: off > b.offset()", .{}, error.InvalidOffset);

    const off2 = @as(i32, @bitCast(b.offset())) - off + size_i32;
    b.place(i32, off2);
}

/// prepends a u32, relative to where it will be written.
pub fn prependUOff(b: *Builder, off: u32) !void {
    b.debug("prependUOff off={}", .{off});
    try b.prep(size_u32, 0); // Ensure alignment is already done.
    if (off > b.offset())
        return err("unreachable: off > b.offset()", .{}, error.InvalidOffset);

    const off2 = b.offset() - off + size_u32;
    b.place(u32, off2);
}

/// initializes bookkeeping for writing a new vector.
///
/// A vector has the following format:
///   <u32: number of elements in this vector>
///   <T: data>+, where T is the type of elements of this vector.
pub fn startVector(b: *Builder, elem_size: i32, num_elems: i32, alignment: i32) !u32 {
    try b.checkNotNested();
    b.nested = true;
    try b.prep(size_u32, elem_size * num_elems);
    try b.prep(alignment, elem_size * num_elems); // Just in case alignment > int.
    return b.offset();
}

/// writes data necessary to finish vector construction.
pub fn endVector(b: *Builder, vector_num_elems: u32) !u32 {
    try b.checkNested();

    // we already made space for this, so write without prependU32
    b.place(u32, vector_num_elems);

    b.nested = false;
    return b.offset();
}

/// serializes slice of table offsets into a vector.
pub fn createVectorOfTables(b: *Builder, offsets: []const u32) !u32 {
    try b.checkNotNested();
    _ = try b.startVector(4, @intCast(offsets.len), 4);
    var i = @as(isize, @bitCast(offsets.len)) - 1;
    while (i >= 0) : (i -= 1)
        _ = try b.prependUOff(offsets[@bitCast(i)]);

    return b.endVector(@intCast(offsets.len));
}

const KeyCompare = fn (u32, u32, []u8) bool;

pub fn createVectorOfSortedTables(
    b: *Builder,
    offsets: []u32,
    comptime keyCompare: KeyCompare,
) !u32 {
    const cmp = struct {
        fn cmp(context: []u8, i: u32, j: u32) bool {
            return keyCompare(i, j, context);
        }
    }.cmp;

    std.mem.sort(u32, offsets, b.bytes.items, cmp);
    return b.createVectorOfTables(offsets);
}

/// Checks if 's' is already written to the buffer before calling createString()
pub fn createSharedString(b: *Builder, s: []const u8) !u32 {
    const gop = try b.shared_strings.getOrPut(b.alloc, s);
    if (gop.found_existing) return gop.value_ptr.*;
    const off = try b.createString(s);
    gop.value_ptr.* = off;
    return off;
}

/// writes a null-terminated []const u8 as a vector.
pub fn createString(b: *Builder, s: []const u8) !u32 {
    try b.checkNotNested();
    b.nested = true;
    b.debug("createString() '{s}'", .{s});
    try b.prep(size_u32, @as(i32, @intCast(s.len + 1)) * size_byte);
    b.place(u8, 0);

    const l: u32 = @intCast(s.len);

    b.head -= l;
    std.mem.copyForwards(u8, b.bytes.items[b.head .. b.head + l], s);

    return b.endVector(@intCast(s.len));
}

/// writes a byte slice as a []const u8 (null-terminated).
pub fn createByteString(b: *Builder, s: []const u8) !u32 {
    try b.checkNotNested();
    b.nested = true;

    try b.prep(size_u32, (@as(i32, @intCast(s.len)) + 1) * size_byte);
    b.place(u8, 0);

    const l: u32 = @intCast(s.len);

    b.head -= l;
    std.mem.copyForwards(u8, b.bytes.items[b.head .. b.head + l], s);

    return b.endVector(@intCast(s.len));
}

/// write a byte vector
pub fn createByteVector(b: *Builder, v: []const u8) !u32 {
    try b.checkNotNested();
    b.nested = true;

    try b.prep(size_u32, @intCast(v.len * size_byte));

    const l: u32 = @intCast(v.len);

    b.head -= l;
    std.mem.copyForwards(u8, b.bytes.items[b.head .. b.head + l], v);

    return b.endVector(@intCast(v.len));
}

fn checkNested(b: *Builder) !void {
    // If you get an error here, you're in an object while trying to write
    // data that belongs outside of an object.
    // To fix this, write non-inline data (like vectors) before creating
    // objects.
    if (!b.nested) return err(
        "Incorrect creation order: must be inside object.",
        .{},
        error.InvalidNesting,
    );
}

fn checkNotNested(b: *Builder) !void {
    // If you hit this, you're trying to construct a Table/Vector/String
    // during the construction of its parent table (between the MyTableBuilder
    // and builder.Finish()).
    // Move the creation of these sub-objects to above the MyTableBuilder to
    // not get this assert.
    // Ignoring this error may appear to work in simple cases, but the reason
    // it is here is that storing objects in-line may cause vtable offsets
    // to not fit anymore. It also leads to vtable duplication.
    if (b.nested) return err(
        "Incorrect creation order: object must not be nested.",
        .{},
        error.InvalidNesting,
    );
}

fn checkFinished(b: *Builder) !void {
    // If you get this error, you're attempting to get access a buffer
    // which hasn't been finished yet. Be sure to call builder.Finish();
    // with your root table.
    // If you really need to access an unfinished buffer, use the Bytes
    // buffer directly.
    if (!b.finished)
        return err(
            "Incorrect use of finishedBytes(): must call 'finish()' first.",
            .{},
            error.NotFinished,
        );
}

/// prepends a T onto the object at vtable slot `o`.
/// If value `x` equals default `d`, then the slot will be set to zero and no
/// other data will be written.
pub fn prependSlot(b: *Builder, comptime T: type, o: u32, x: T, d: T) !void {
    if (x != d) {
        try b.prepend(T, x);
        b.slot(o);
    }
}

/// prepends an u32 onto the object at vtable slot `o`.
/// If value `x` equals default `d`, then the slot will be set to zero and no
/// other data will be written.
pub fn prependSlotUOff(b: *Builder, o: u32, x: u32, d: u32) !void {
    if (x != d) {
        try b.prependUOff(x);
        b.slot(o);
    }
}

// prepends a struct onto the object at vtable slot `o`.
// Structs are stored inline, so nothing additional is being added.
// In generated code, `d` is always 0.
pub fn prependSlotStruct(b: *Builder, voffset: u32, x: u32, d: u32) !void {
    if (x != d) {
        try b.checkNested();
        if (x != b.offset()) return err(
            "inline data write outside of object",
            .{},
            error.InvalidOffset,
        );
        b.slot(voffset);
    }
}

/// sets the vtable key `voffset` to the current location in the buffer.
pub fn slot(b: *Builder, slotnum: u32) void {
    b.vtable.items[slotnum] = b.offset();
}

/// finalizes a buffer, pointing to the given `rootTable`.
/// as well as applys a file identifier
pub fn finishWithFileIdentifier(b: *Builder, rootTable: u32, fid: Fid) !void {
    // In order to add a file identifier to the flatbuffer message, we need
    // to prepare an alignment and file identifier length
    try b.prep(@bitCast(b.minalign), size_i32 + file_identifier_len);
    var i = file_identifier_len - 1;
    while (i >= 0) : (i -= 1) {
        // place the file identifier
        b.place(u8, fid[@as(u32, @bitCast(i))]);
    }
    // finish
    return b.finish(rootTable);
}

/// finalizes a buffer, pointing to the given `rootTable`.
/// The buffer is prefixed with the size of the buffer, excluding the size
/// of the prefix itself.
pub fn finishSizePrefixed(b: *Builder, rootTable: u32) !void {
    return b.finishPrefixed(rootTable, true);
}

/// finalizes a buffer, pointing to the given `rootTable`
/// and applies a file identifier. The buffer is prefixed with the size of the buffer,
/// excluding the size of the prefix itself.
pub fn finishSizePrefixedWithFileIdentifier(b: *Builder, rootTable: u32, fid: [4]u8) !void {
    // In order to add a file identifier and size prefix to the flatbuffer message,
    // we need to prepare an alignment, a size prefix length, and file identifier length
    try b.prep(@bitCast(b.minalign), size_i32 + file_identifier_len + size_prefix_length);
    var i = file_identifier_len - 1;
    while (i >= 0) : (i -= 1) {
        // place the file identifier
        b.place(u8, fid[@as(u32, @bitCast(i))]);
    }
    // finish
    return b.finishPrefixed(rootTable, true);
}

/// finalizes a buffer, pointing to the given `rootTable`.
pub fn finish(b: *Builder, rootTable: u32) !void {
    try b.finishPrefixed(rootTable, false);
}

/// finalizes a buffer, pointing to the given `rootTable`
/// with a size prefix.
pub fn finishPrefixed(b: *Builder, root_table: u32, size_prefix: bool) !void {
    try b.checkNotNested();

    if (size_prefix)
        try b.prep(@bitCast(b.minalign), size_u32 + size_prefix_length)
    else
        try b.prep(@bitCast(b.minalign), size_u32);

    try b.prependUOff(root_table);
    if (size_prefix) b.place(u32, b.offset());
    b.finished = true;
}

/// compares an unwritten vtable to a written vtable.
pub fn vtableEqual(a: []const u32, objectStart: u32, b: []const u8) bool {
    if (a.len * size_u16 != b.len) return false;

    for (0..a.len) |i| {
        const x = read(u16, b[i * size_u16 .. (i + 1) * size_u16]);

        // Skip vtable entries that indicate a default value.
        if (x == 0 and a[i] == 0) continue;

        const y = objectStart - a[i];
        if (x != y) return false;
    }
    return true;
}

/// prepends a T to the Builder buffer.
/// Aligns and checks for space.
pub fn prepend(b: *Builder, comptime T: type, x: T) !void {
    try b.prep(@sizeOf(T), 0);
    b.place(T, x);
}

/// prepends a T to the Builder, without checking for space.
pub fn place(b: *Builder, comptime T: type, x: T) void {
    b.debug("place{s} b.head={} x={}", .{ @typeName(T), b.head, x });
    b.head -= @sizeOf(T);
    write(T, b.bytes.items[b.head..], x);
}
