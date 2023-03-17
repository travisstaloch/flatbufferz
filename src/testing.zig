//! test helpers
//! i have copied std.testing.expectEqualDeep() and only changed its return
//! error set type. this allows it to be used with recursive types.

const std = @import("std");

/// This function is intended to be used only in tests. When the two values are not
/// deeply equal, prints diagnostics to stderr to show exactly how they are not equal,
/// then returns a test failure error.
/// `actual` is casted to the type of `expected`.
///
/// Deeply equal is defined as follows:
/// Primitive types are deeply equal if they are equal using  `==` operator.
/// Struct values are deeply equal if their corresponding fields are deeply equal.
/// Container types(like Array/Slice/Vector) deeply equal when their corresponding elements are deeply equal.
/// Pointer values are deeply equal if values they point to are deeply equal.
///
/// Note: Self-referential structs are not supported (e.g. things like std.SinglyLinkedList)
pub fn expectEqualDeep(expected: anytype, actual: @TypeOf(expected)) error{TestExpectedEqual}!void {
    switch (@typeInfo(@TypeOf(actual))) {
        .NoReturn,
        .Opaque,
        .Frame,
        .AnyFrame,
        => @compileError("value of type " ++ @typeName(@TypeOf(actual)) ++ " encountered"),

        .Undefined,
        .Null,
        .Void,
        => return,

        .Type => {
            if (actual != expected) {
                std.debug.print("expected type {s}, found type {s}\n", .{ @typeName(expected), @typeName(actual) });
                return error.TestExpectedEqual;
            }
        },

        .Bool,
        .Int,
        .Float,
        .ComptimeFloat,
        .ComptimeInt,
        .EnumLiteral,
        .Enum,
        .Fn,
        .ErrorSet,
        => {
            if (actual != expected) {
                std.debug.print("expected {}, found {}\n", .{ expected, actual });
                return error.TestExpectedEqual;
            }
        },

        .Pointer => |pointer| {
            switch (pointer.size) {
                // We have no idea what is behind those pointers, so the best we can do is `==` check.
                .C, .Many => {
                    if (actual != expected) {
                        std.debug.print("expected {*}, found {*}\n", .{ expected, actual });
                        return error.TestExpectedEqual;
                    }
                },
                .One => {
                    // Length of those pointers are runtime value, so the best we can do is `==` check.
                    switch (@typeInfo(pointer.child)) {
                        .Fn, .Opaque => {
                            if (actual != expected) {
                                std.debug.print("expected {*}, found {*}\n", .{ expected, actual });
                                return error.TestExpectedEqual;
                            }
                        },
                        else => try expectEqualDeep(expected.*, actual.*),
                    }
                },
                .Slice => {
                    if (expected.len != actual.len) {
                        std.debug.print("Slice len not the same, expected {d}, found {d}\n", .{ expected.len, actual.len });
                        return error.TestExpectedEqual;
                    }
                    var i: usize = 0;
                    while (i < expected.len) : (i += 1) {
                        expectEqualDeep(expected[i], actual[i]) catch |e| {
                            std.debug.print("index {d} incorrect. expected {any}, found {any}\n", .{
                                i, expected[i], actual[i],
                            });
                            return e;
                        };
                    }
                },
            }
        },

        .Array => |_| {
            if (expected.len != actual.len) {
                std.debug.print("Array len not the same, expected {d}, found {d}\n", .{ expected.len, actual.len });
                return error.TestExpectedEqual;
            }
            var i: usize = 0;
            while (i < expected.len) : (i += 1) {
                expectEqualDeep(expected[i], actual[i]) catch |e| {
                    std.debug.print("index {d} incorrect. expected {any}, found {any}\n", .{
                        i, expected[i], actual[i],
                    });
                    return e;
                };
            }
        },

        .Vector => |info| {
            if (info.len != @typeInfo(@TypeOf(actual)).Vector.len) {
                std.debug.print("Vector len not the same, expected {d}, found {d}\n", .{ info.len, @typeInfo(@TypeOf(actual)).Vector.len });
                return error.TestExpectedEqual;
            }
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                expectEqualDeep(expected[i], actual[i]) catch |e| {
                    std.debug.print("index {d} incorrect. expected {any}, found {any}\n", .{
                        i, expected[i], actual[i],
                    });
                    return e;
                };
            }
        },

        .Struct => |structType| {
            inline for (structType.fields) |field| {
                expectEqualDeep(@field(expected, field.name), @field(actual, field.name)) catch |e| {
                    std.debug.print("Field {s} incorrect. expected {any}, found {any}\n", .{ field.name, @field(expected, field.name), @field(actual, field.name) });
                    return e;
                };
            }
        },

        .Union => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Unable to compare untagged union values");
            }

            const Tag = std.meta.Tag(@TypeOf(expected));

            const expectedTag = @as(Tag, expected);
            const actualTag = @as(Tag, actual);

            try std.testing.expectEqual(expectedTag, actualTag);

            // we only reach this loop if the tags are equal
            switch (expected) {
                inline else => |val, tag| {
                    try expectEqualDeep(val, @field(actual, @tagName(tag)));
                },
            }
        },

        .Optional => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqualDeep(expected_payload, actual_payload);
                } else {
                    std.debug.print("expected {any}, found null\n", .{expected_payload});
                    return error.TestExpectedEqual;
                }
            } else {
                if (actual) |actual_payload| {
                    std.debug.print("expected null, found {any}\n", .{actual_payload});
                    return error.TestExpectedEqual;
                }
            }
        },

        .ErrorUnion => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqualDeep(expected_payload, actual_payload);
                } else |actual_err| {
                    std.debug.print("expected {any}, found {any}\n", .{ expected_payload, actual_err });
                    return error.TestExpectedEqual;
                }
            } else |expected_err| {
                if (actual) |actual_payload| {
                    std.debug.print("expected {any}, found {any}\n", .{ expected_err, actual_payload });
                    return error.TestExpectedEqual;
                } else |actual_err| {
                    try expectEqualDeep(expected_err, actual_err);
                }
            }
        },
    }
}
