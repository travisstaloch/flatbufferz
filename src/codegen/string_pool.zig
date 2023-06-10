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
        if (self.lookup.getKey(string)) |s| {
            return s;
        } else {
            const owned = try self.allocator.alloc(u8, string.len);
            @memcpy(owned, string);
            try self.data.append(self.allocator, owned);
            try self.lookup.put(self.allocator, owned, {});
            return owned;
        }
    }
};
