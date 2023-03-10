const std = @import("std");

pub fn todo(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.panic("TODO " ++ fmt, args);
}

pub const panicf = std.debug.panic;
pub fn ptrAlign(comptime Ptr: type) comptime_int {
    return @typeInfo(Ptr).Pointer.alignment;
}

pub fn ptrAlignCast(comptime Ptr: type, ptr: anytype) Ptr {
    return @ptrCast(Ptr, @alignCast(ptrAlign(Ptr), ptr));
}
