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

pub fn encode(comptime T: type, item: T, writer: *types.BufferedWriter) !void {
    inline for (@typeInfo(T).Struct.fields) |field, i| {
        switch (@typeInfo(field.field_type)) {
            .Struct => {
                if (@hasDecl(field.field_type, "field_meta")) {
                    try field.field_type.field_meta.encodeInto(types.BufferedWriter, writer);
                    try @field(item, field.name).encodeInto(types.BufferedWriter, writer);
                } else {
                    std.debug.warn("{} - unknown struct\n", field.name);
                }
            },
            else => {
                std.debug.warn("{} - not a struct\n", field.name);
            },
        }
    }
}

pub fn marshal(comptime T: type, allocator: *std.mem.Allocator, item: T) ![]u8 {
    var writer = types.BufferedWriter.init(allocator);
    errdefer writer.deinit();

    try encode(T, item, &writer);

    return writer.toOwnedSlice();
}

pub fn unmarshal(comptime T: type, allocator: *std.mem.Allocator, bytes: []u8) !T {
    var result = init(T);
    errdefer deinit(T, &result);

    var cursor = usize(0);
    while (cursor < bytes.len) {
        var len: usize = undefined;
        const info = try types.FieldMeta.decode(bytes[cursor..], &len);
        cursor += len;

        inline for (@typeInfo(T).Struct.fields) |field, i| {
            switch (@typeInfo(field.field_type)) {
                .Struct => {
                    if (info.number == field.field_type.field_meta.number) {
                        if (@hasDecl(field.field_type, "decodeFromAlloc")) {
                            cursor += try @field(result, field.name).decodeFromAlloc(bytes[cursor..], allocator);
                        } else {
                            cursor += try @field(result, field.name).decodeFrom(bytes[cursor..]);
                        }
                        break;
                    }
                },
                else => {
                    std.debug.warn("{} - not a struct\n", field.name);
                },
            }
        }
    }

    inline for (@typeInfo(T).Struct.fields) |field, i| {
        switch (@typeInfo(field.field_type)) {
            .Struct => {
                if (@hasDecl(field.field_type, "decodeComplete")) {
                    @field(result, field.name).decodeComplete();
                }
            },
            else => {
                std.debug.warn("{} - not a struct\n", field.name);
            },
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

pub fn deinit(comptime T: type, msg: *T) void {
    inline for (@typeInfo(T).Struct.fields) |field, i| {
        switch (@typeInfo(field.field_type)) {
            .Struct => {
                if (@hasDecl(field.field_type, "deinit")) {
                    @field(msg, field.name).deinit();
                }
            },
            else => {
                std.debug.warn("{} - not a struct\n", field.name);
            },
        }
    }
}

test "end-to-end" {
    const Example = struct {
        sint: types.Sint64(1),
        str: types.String(12),
        boo: types.Bool(10),
    };

    var start = init(Example);
    testing.expectEqual(i64(0), start.sint.data);
    testing.expectEqual(false, start.boo.data);
    testing.expectEqual(start.str.data, "");
    testing.expectEqual(start.str.allocator, null);

    start.sint.data = -17;
    start.boo.data = true;
    start.str.data = "weird";

    const binary = try marshal(Example, std.heap.direct_allocator, start);
    defer std.heap.direct_allocator.free(binary);

    var result = try unmarshal(Example, std.heap.direct_allocator, binary);
    testing.expectEqual(start.sint.data, result.sint.data);
    testing.expectEqual(start.boo.data, result.boo.data);
    testing.expectEqualSlices(u8, start.str.data, result.str.data);
    testing.expectEqual(std.heap.direct_allocator, result.str.allocator.?);

    deinit(Example, &result);
    testing.expectEqual(result.str.data, "");
    testing.expectEqual(result.str.allocator, null);
}
