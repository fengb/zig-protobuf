const std = @import("std");
const testing = std.testing;

const types = @import("types.zig");

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
        const uint = types.Uint64{ .data = (@intCast(u64, self.number) << 3) + @enumToInt(self.typ) };
        return uint.encodeInto(buffer);
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
        var out: ?[]const u8 = [_]u8{};

        item: T,
        frame: @Frame(spin),

        pub fn init(item: T) Self {
            return Self{
                .item = item,
                .frame = async spin(item),
            };
        }

        fn spin(item: T) void {
            var buffer: [1000]u8 = undefined;
            var bufslice = buffer[0..];

            inline for (@typeInfo(T).Struct.fields) |field, i| {
                const fieldInfo = FieldInfo{
                    .typ = .Varint, // TODO: correct field type
                    .number = @intCast(u64, i + 1),
                };
                Self.out = fieldInfo.encodeInto(bufslice);
                suspend;

                switch (@typeInfo(field.field_type)) {
                    .Struct => {
                        if (@hasDecl(field.field_type, "encodeInto")) {
                            Self.out = @field(item, field.name).encodeInto(bufslice);
                            suspend;
                        } else {
                            std.debug.warn("{} - unknown struct\n", field.name);
                        }
                    },
                    else => {
                        std.debug.warn("{} - not a struct\n", field.name);
                    },
                }
            }
            Self.out = null;
        }

        pub fn next(self: *Self) ?[]const u8 {
            if (out) |result| {
                resume self.frame;
                return result;
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
        @"type": types.Sint64,
        reps: []const i64 = [_]i64{},

        allocator: ?*std.mem.Allocator = null,
    };

    const start = Example{
        .label = "hello",
        .@"type" = types.Sint64{ .data = 17 },
        .reps = [_]i64{ 1, 2, 3 },
    };
    const binary = try marshal(Example, std.heap.direct_allocator, start);
    //const result = unmarshal(Example, std.heap.direct_allocator, binary);

    //testing.expectEqualSlices(u8, start.label, result.label);
    //testing.expectEqual(start.@"type", result.@"type");
    //testing.expectEqualSlices(i64, start.reps, result.reps);
}
