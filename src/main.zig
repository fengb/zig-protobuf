const std = @import("std");
const testing = std.testing;

const Varint64 = struct {
    uint: u64,
    len: u10,

    pub fn initUint(n: u64) Varint64 {
        return Varint64{
            .uint = n,
            .len = 0, // FIXME
        };
    }

    pub fn initInt(n: i64) Varint64 {
        return initUint(@bitCast(u64, n));
    }

    pub fn initSint(n: i64) Varint64 {
        return initUint(@intCast(u64, (n << 1) ^ (n >> 63)));
    }

    pub fn decode(bytes: []const u8) !Varint64 {
        var result = Varint64{
            .uint = 0,
            .len = undefined,
        };

        for (bytes) |byte, i| {
            if (i >= 10) {
                return error.Whoops;
            }
            result.uint += @intCast(u64, 0x7F & byte) << (7 * @intCast(u3, i));
            if (byte & 0x80 == 0) {
                result.len = @intCast(u3, i + 1);
                return result;
            }
        }
        return error.Whoops;
    }

    pub fn int(self: Varint64) i64 {
        return @bitCast(i64, self.uint);
    }

    pub fn sint(self: Varint64) i64 {
        const raw = @intCast(i64, self.uint >> 1);
        return if (@mod(self.uint, 2) == 0) raw else -(raw + 1);
    }
};

test "Varint64" {
    var vint = try Varint64.decode([_]u8{1});
    testing.expectEqual(u64(1), vint.uint);

    vint = try Varint64.decode([_]u8{ 0b10101100, 0b00000010 });
    testing.expectEqual(u64(300), vint.uint);

    vint = try Varint64.decode([_]u8{ 0b10010110, 0b00000001 });
    testing.expectEqual(u64(150), vint.uint);

    vint = Varint64.initUint(3);
    testing.expectEqual(u64(3), vint.uint);

    vint = Varint64.initInt(-1);
    testing.expectEqual(u64(std.math.maxInt(u64)), vint.uint);
    testing.expectEqual(i64(-1), vint.int());

    vint = Varint64.initSint(-1);
    testing.expectEqual(u64(1), vint.uint);
    testing.expectEqual(i64(-1), vint.sint());

    vint = Varint64.initSint(2147483647);
    testing.expectEqual(u64(4294967294), vint.uint);
    testing.expectEqual(i64(2147483647), vint.sint());

    vint = Varint64.initSint(-2147483648);
    testing.expectEqual(u64(4294967295), vint.uint);
    testing.expectEqual(i64(-2147483648), vint.sint());
}

const FieldInfo = struct {
    typ: Type,
    number: u61,

    pub fn init(value: u64) FieldInfo {
        return FieldInfo{
            .typ = @intToEnum(Type, @truncate(u3, value)),
            .number = @intCast(u61, value >> 3),
        };
    }

    const Type = enum(u3) {
        Varint = 0,
        _64bit = 1,
        LengthDelimited = 2,
        StartGroup = 3,
        EndGroup = 4,
        _32bit = 5,
    };
};

test "FieldInfo" {
    const field = FieldInfo.init(8);
    testing.expectEqual(FieldInfo.Type.Varint, field.typ);
    testing.expectEqual(u61(1), field.number);
}

pub fn StreamingMarshal(comptime T: type) type {
    return struct {
        const Self = @This();
        const fields = @typeInfo(T).Struct.fields;

        item: T,
        buffer: [1000]u8 = undefined,

        pub fn init(item: T) Self {
            return Self{
                .item = item,
            };
        }

        pub fn next(self: Self) ?[]u8 {
            inline for (@typeInfo(T).Struct.fields) |field, i| {
                std.debug.warn("{} {}\n", i, field.name);
            }
            return null;
        }
    };
}

pub fn marshal(comptime T: type, allocator: *std.mem.Allocator, item: T) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    const stream = StreamingMarshal(T).init(item);
    while (stream.next()) |data| {
        std.debug.warn("{x}\n", data);
        try buffer.appendSlice(data);
    }

    return buffer.toOwnedSlice();
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
    const binary = try marshal(Example, std.heap.direct_allocator, start);
    const result = unmarshal(Example, std.heap.direct_allocator, binary);

    //testing.expectEqualSlices(u8, start.label, result.label);
    //testing.expectEqual(start.@"type", result.@"type");
    //testing.expectEqualSlices(i64, start.reps, result.reps);
}
