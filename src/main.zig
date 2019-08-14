const std = @import("std");
const testing = std.testing;

pub fn marshal(comptime T: type, item: T) []u8 {
    return [_]u8{};
}

pub fn unmarshal(comptime T: type, allocator: *std.mem.Allocator, bytes: []u8) T {
    return T{};
}

test "marshalling" {
    const Example = struct {
        label: []const u8 = "",
        @"type": ?i32 = 77,
        reps: []const i64 = [_]i64{},

        allocator: ?*std.mem.Allocator = null,
    };

    const start = Example{
        .label = "hello",
        .@"type" = 17,
        .reps = [_]i64{ 1, 2, 3 },
    };
    const binary = marshal(Example, start);
    const result = unmarshal(Example, std.heap.direct_allocator, binary);

    testing.expectEqualSlices(u8, start.label, result.label);
    testing.expectEqual(start.@"type", result.@"type");
    testing.expectEqualSlices(i64, start.reps, result.reps);
}
