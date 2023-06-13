const std = @import("std");

const Allocator = std.mem.Allocator;
pub const StringPool = struct {
    const Self = @This();
    const Data = std.ArrayListUnmanaged([]const u8);
    const Lookup = std.StringHashMapUnmanaged(void);

    allocator: Allocator,
    data: Data,
    lookup: Lookup,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .data = .{},
            .lookup = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.lookup.deinit(self.allocator);
        for (self.data.items) |s| self.allocator.free(s);
        self.data.deinit(self.allocator);
    }

    pub fn getOrPut(self: *Self, string: []const u8) ![]const u8 {
        const get_or_put = try self.lookup.getOrPut(self.allocator, string);
        if (!get_or_put.found_existing) {
            const owned = try self.allocator.alloc(u8, string.len);
            @memcpy(owned, string);
            try self.data.append(self.allocator, owned);
            get_or_put.key_ptr.* = owned;
        }
        return get_or_put.key_ptr.*;
    }

    pub fn getOrPutFmt(self: *Self, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const value = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(value);
        return try self.getOrPut(value);
    }
};
