const std = @import("std");
const testing = std.testing;

const Varint64 = struct {
    value: u64,
    len: u10,

    pub fn decode(bytes: []const u8) !Varint64 {
        var result = Varint64{
            .value = 0,
            .len = undefined,
        };

        for (bytes) |byte, i| {
            if (i >= 10) {
                return error.Whoops;
            }
            result.value += @intCast(u64, 0x7F & byte) << (7 * @intCast(u3, i));
            if (byte & 0x80 == 0) {
                result.len = @intCast(u3, i + 1);
                return result;
            }
        }
        return error.Whoops;
    }
};

test "Varint64" {
    var vint = try Varint64.decode([_]u8{1});
    testing.expectEqual(u64(1), vint.value);

    vint = try Varint64.decode([_]u8{ 0b10101100, 0b00000010 });
    testing.expectEqual(u64(300), vint.value);

    vint = try Varint64.decode([_]u8{ 0b10010110, 0b00000001 });
    testing.expectEqual(u64(150), vint.value);
}

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
