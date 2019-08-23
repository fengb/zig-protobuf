const std = @import("std");
const builtin = @import("builtin");
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

pub const Repeated = types.Repeated;

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
                        if (@hasDecl(field.field_type, "field_info")) {
                            suspend;
                            Self.out = field.field_type.field_info.encodeInto(bufslice);

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

    while (stream.next()) |data| {
        try buffer.appendSlice(data);
    }

    return buffer.toOwnedSlice();
}

pub fn unmarshal(comptime T: type, allocator: *std.mem.Allocator, bytes: []u8) !T {
    var result = init(T);

    var cursor = usize(0);
    while (cursor < bytes.len) {
        var len: usize = undefined;
        const info = try types.FieldInfo.decode(bytes[cursor..], &len);
        cursor += len;

        inline for (@typeInfo(T).Struct.fields) |field, i| {
            switch (@typeInfo(field.field_type)) {
                .Struct => {
                    if (info.number == field.field_type.field_info.number) {
                        try @field(result, field.name).decodeFrom(bytes[cursor..], &len);
                        cursor += len;
                        break;
                    }
                },
                else => {
                    std.debug.warn("{} - not a struct\n", field.name);
                },
            }
        }
    }
    return result;
}

pub fn init(comptime T: type) T {
    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |field, i| {
        switch (@typeInfo(field.field_type)) {
            .Struct => {
                @field(result, field.name) = field.field_type{};
            },
            else => {
                std.debug.warn("{} - not a struct\n", field.name);
            },
        }
    }
    return result;
}

test "marshalling" {
    const Example = struct {
        sint: types.Sint64(1),
        boo: types.Bool(10),
    };

    var start = init(Example);
    testing.expectEqual(i64(0), start.sint.data);
    testing.expectEqual(false, start.boo.data);

    start.sint.data = -17;
    start.boo.data = true;

    const binary = try marshal(Example, std.heap.direct_allocator, start);
    const result = try unmarshal(Example, std.heap.direct_allocator, binary);
    testing.expectEqual(start.sint, result.sint);
}
