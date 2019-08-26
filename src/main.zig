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

pub fn encodeInto(comptime T: type, item: T, out_stream: var) !void {
    inline for (@typeInfo(T).Struct.fields) |field, i| {
        switch (@typeInfo(field.field_type)) {
            .Struct => {
                if (@hasDecl(field.field_type, "field_meta")) {
                    try field.field_type.field_meta.encodeInto(out_stream);
                    try @field(item, field.name).encodeInto(out_stream);
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

pub fn decodeFrom(comptime T: type, allocator: *std.mem.Allocator, in_stream: var) !T {
    var result = init(T);
    errdefer deinit(T, &result);

    while (types.FieldMeta.decode(in_stream)) |meta| {
        inline for (@typeInfo(T).Struct.fields) |field, i| {
            switch (@typeInfo(field.field_type)) {
                .Struct => {
                    if (meta.number == field.field_type.field_meta.number) {
                        if (@hasDecl(field.field_type, "decodeFromAlloc")) {
                            try @field(result, field.name).decodeFromAlloc(in_stream, allocator);
                        } else {
                            try @field(result, field.name).decodeFrom(in_stream);
                        }
                        break;
                    }
                },
                else => {
                    std.debug.warn("{} - not a struct\n", field.name);
                },
            }
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
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
    testing.expectEqual(i64(0), start.sint.value);
    testing.expectEqual(false, start.boo.value);
    testing.expectEqual(start.str.value, "");
    testing.expectEqual(start.str.allocator, null);

    start.sint.value = -17;
    start.boo.value = true;
    start.str.value = "weird";

    var buf: [1000]u8 = undefined;
    var out = std.io.SliceOutStream.init(buf[0..]);
    try encodeInto(Example, start, &out.stream);

    var mem_in = std.io.SliceInStream.init(out.getWritten());
    var result = try decodeFrom(Example, std.heap.direct_allocator, &mem_in.stream);
    testing.expectEqual(start.sint.value, result.sint.value);
    testing.expectEqual(start.boo.value, result.boo.value);
    testing.expectEqualSlices(u8, start.str.value, result.str.value);
    testing.expectEqual(std.heap.direct_allocator, result.str.allocator.?);

    deinit(Example, &result);
    testing.expectEqual(result.str.value, "");
    testing.expectEqual(result.str.allocator, null);
}
