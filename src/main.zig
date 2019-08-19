const std = @import("std");
const testing = std.testing;

const types = @import("types.zig");

pub const Double = types.Double;
pub const Float = types.Float;
pub const Int64 = types.Int64;
pub const Int32 = types.Int32;
pub const Uint64 = types.Uint64;
pub const Uint32 = types.Uint32;
pub const Sint64 = types.Sint64;
pub const Sint32 = types.Sint32;
pub const Fixed64 = types.Fixed64;
pub const Fixed32 = types.Fixed32;
pub const Sfixed64 = types.Sfixed64;
pub const Sfixed32 = types.Sfixed32;
pub const Bool = types.Bool;
pub const Bytes = types.Bytes;
pub const String = types.String;

const FieldInfo = struct {
    wire_type: types.WireType,
    number: u61,

    pub fn init(value: u64) FieldInfo {
        return FieldInfo{
            .wire_type = @intToEnum(types.WireType, @truncate(u3, value)),
            .number = @intCast(u61, value >> 3),
        };
    }

    pub fn encodeInto(self: FieldInfo, buffer: []u8) []u8 {
        const uint = types.Uint64{ .data = (@intCast(u64, self.number) << 3) + @enumToInt(self.wire_type) };
        return uint.encodeInto(buffer);
    }
};

test "FieldInfo" {
    const field = FieldInfo.init(8);
    testing.expectEqual(types.WireType.Varint, field.wire_type);
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
                switch (@typeInfo(field.field_type)) {
                    .Struct => {
                        if (@hasDecl(field.field_type, "encodeInto")) {
                            const fieldInfo = FieldInfo{
                                .wire_type = field.field_type.wire_type,
                                .number = @intCast(u64, i + 1),
                            };
                            suspend;
                            Self.out = fieldInfo.encodeInto(bufslice);

                            suspend;
                            Self.out = @field(item, field.name).encodeInto(bufslice);
                        } else {
                            std.debug.warn("{} - unknown struct\n", field.name);
                        }
                    },
                    else => {
                        std.debug.warn("{} - not a struct\n", field.name);
                    },
                }
            }
            suspend;
            Self.out = null;
        }

        pub fn next(self: *Self) ?[]const u8 {
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

    std.debug.warn("\n");
    while (stream.next()) |data| {
        std.debug.warn("0x{x} ", data);
        try buffer.appendSlice(data);
    }
    std.debug.warn("\n");

    return buffer.toOwnedSlice();
}

pub fn unmarshal(comptime T: type, allocator: *std.mem.Allocator, bytes: []u8) T {
    return T{};
}

test "marshalling" {
    const Example = struct {
        sint: types.Sint64,
    };

    const start = Example{
        .sint = types.Sint64{ .data = 17 },
    };
    const binary = try marshal(Example, std.heap.direct_allocator, start);
    //const result = unmarshal(Example, std.heap.direct_allocator, binary);

    //testing.expectEqualSlices(u8, start.label, result.label);
    //testing.expectEqual(start.@"type", result.@"type");
    //testing.expectEqualSlices(i64, start.reps, result.reps);
}
