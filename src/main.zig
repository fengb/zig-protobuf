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

    pub fn encodeInto(self: Varint64, buffer: []u8) []u8 {
        var value = self.uint;
        if (value == 0) {
            buffer[0] = 0;
            return buffer[0..1];
        }

        var i = usize(0);
        while (value > 0) : (i += 1) {
            buffer[i] = u8(0x80) + @truncate(u7, value);
            value >>= 7;
        }
        buffer[i - 1] = buffer[i - 1] & 0x7F;
        return buffer[0..i];
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
            result.uint += @intCast(u64, 0x7F & byte) << (7 * @intCast(u6, i));
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

    var buf: [1000]u8 = undefined;
    vint = Varint64.initSint(-2147483648);
    var result = vint.encodeInto(buf[0..]);
    const new = try Varint64.decode(result);
    testing.expectEqual(vint.uint, new.uint);
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

    pub fn encodeInto(self: FieldInfo, buffer: []u8) []u8 {
        const val = (@intCast(u64, self.number) << 3) + @enumToInt(self.typ);
        return Varint64.initUint(val).encodeInto(buffer);
    }
};

test "FieldInfo" {
    const field = FieldInfo.init(8);
    testing.expectEqual(FieldInfo.Type.Varint, field.typ);
    testing.expectEqual(u61(1), field.number);
}

pub fn StreamingMarshal(comptime T: type) type {
    return struct {
        const Self = @This();

        // TODO: this is so terrible.
        // Temporarily sticking this here because I can't make spin a method due to circular references
        var out: ?[]u8 = [_]u8{};

        item: T,
        frame: @Frame(spin),

        pub fn init(item: T) Self {
            return Self{
                .item = item,
                .frame = async spin(),
            };
        }

        fn spin() void {
            var buffer: [1000]u8 = undefined;

            inline for (@typeInfo(T).Struct.fields) |field, i| {
                suspend;
                const fieldInfo = FieldInfo{
                    .typ = .Varint,
                    .number = @intCast(u64, i),
                };
                // Work around copy elision bug
                const copy = fieldInfo.encodeInto(buffer[0..]);
                Self.out = copy;
            }
            Self.out = null;
        }

        pub fn next(self: *Self) ?[]u8 {
            if (out != null) {
                resume self.frame;
                return out;
            }
            return null;
        }
    };
}

pub fn marshal(comptime T: type, allocator: *std.mem.Allocator, item: T) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    var stream = StreamingMarshal(T).init(item);

    while (stream.next()) |data| {
        std.debug.warn("data: 0x{x}\n", data);
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
