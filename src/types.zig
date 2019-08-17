const std = @import("std");
const testing = std.testing;

pub const WireType = enum(u3) {
    Varint = 0,
    _64bit = 1,
    LengthDelimited = 2,
    StartGroup = 3,
    EndGroup = 4,
    _32bit = 5,
};

pub const Uint64 = struct {
    data: u64,

    pub const wire_type = WireType.Varint;

    pub fn encodeInto(self: Uint64, buffer: []u8) []u8 {
        var i = usize(0);
        var value = self.data;
        while (value > 0) : (i += 1) {
            buffer[i] = u8(0x80) + @truncate(u7, value);
            value >>= 7;
        }
        buffer[i - 1] &= 0x7F;
        return buffer[0..i];
    }

    pub fn decode(bytes: []const u8, len: *usize) !Uint64 {
        var value = u64(0);

        for (bytes) |byte, i| {
            if (i >= 10) {
                return error.Whoops;
            }
            value += @intCast(u64, 0x7F & byte) << (7 * @intCast(u6, i));
            if (byte & 0x80 == 0) {
                len.* = i + 1;
                return Uint64{ .data = value };
            }
        }
        return error.Whoops;
    }
};

pub const Int64 = struct {
    data: i64,

    pub const wire_type = WireType.Varint;

    pub fn encodeInto(self: Int64, buffer: []u8) []u8 {
        const uint = Uint64{ .data = @bitCast(i64, self.data) };
        return uint.encodeInto(buffer);
    }

    pub fn decode(bytes: []const u8, len: *usize) !Int64 {
        const uint = try Uint64.decode(bytes, len);
        return Int64{ .data = @bitCast(i64, uint.data) };
    }
};

pub const Sint64 = struct {
    data: i64,

    pub const wire_type = WireType.Varint;

    pub fn encodeInto(self: Sint64, buffer: []u8) []u8 {
        const uint = Uint64{ .data = @bitCast(u64, (self.data << 1) ^ (self.data >> 63)) };
        return uint.encodeInto(buffer);
    }

    pub fn decode(bytes: []const u8, len: *usize) !Sint64 {
        const uint = try Uint64.decode(bytes, len);
        const raw = @bitCast(i64, uint.data >> 1);
        return Sint64{ .data = if (@mod(uint.data, 2) == 0) raw else -(raw + 1) };
    }
};

pub const Uint32 = Varint32From64(Uint64, u32);
pub const Int32 = Varint32From64(Int64, i32);
pub const Sint32 = Varint32From64(Sint64, i32);

fn Varint32From64(comptime SourceType: type, comptime TargetPrimitive: type) type {
    return struct {
        const Self = @This();

        data: TargetPrimitive,

        pub const wire_type = WireType.Varint;

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return (SourceType{ .data = self.data }).encodeInto(buffer);
        }

        pub fn decode(bytes: []const u8, len: *usize) !Self {
            const source = try SourceType.decode(bytes, len);
            return Self{ .data = @intCast(TargetPrimitive, source.data) };
        }
    };
}

fn fieldType(comptime T: type, comptime name: []const u8) type {
    for (@typeInfo(T).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return field.field_type;
        }
    }

    unreachable;
}

test "Varint" {
    var len: usize = 0;

    var uint = try Uint64.decode([_]u8{1}, &len);
    testing.expectEqual(u64(1), uint.data);

    uint = try Uint64.decode([_]u8{ 0b10101100, 0b00000010 }, &len);
    testing.expectEqual(u64(300), uint.data);

    uint = try Uint64.decode([_]u8{ 0b10010110, 0b00000001 }, &len);
    testing.expectEqual(u64(150), uint.data);

    var buf1: [1000]u8 = undefined;
    var buf2: [1000]u8 = undefined;
    testing.expectEqualSlices(
        u8,
        (Int64{ .data = -1 }).encodeInto(buf1[0..]),
        (Uint64{ .data = std.math.maxInt(u64) }).encodeInto(buf2[0..]),
    );

    testing.expectEqualSlices(
        u8,
        (Sint64{ .data = -1 }).encodeInto(buf1[0..]),
        (Uint64{ .data = 1 }).encodeInto(buf2[0..]),
    );

    testing.expectEqualSlices(
        u8,
        (Sint64{ .data = 2147483647 }).encodeInto(buf1[0..]),
        (Uint64{ .data = 4294967294 }).encodeInto(buf2[0..]),
    );

    testing.expectEqualSlices(
        u8,
        (Sint64{ .data = -2147483648 }).encodeInto(buf1[0..]),
        (Uint64{ .data = 4294967295 }).encodeInto(buf2[0..]),
    );

    @"fuzz": {
        var rng = std.rand.DefaultPrng.init(0);

        inline for ([_]type{ Uint64, Int64, Sint64, Uint32, Int32, Sint32 }) |T| {
            const data_type = fieldType(T, "data");

            var i = usize(0);
            while (i < 100) : (i += 1) {
                var buf: [1000]u8 = undefined;

                const ref = T{ .data = rng.random.int(data_type) };
                const bytes = ref.encodeInto(buf[0..]);
                const converted = try T.decode(bytes, &len);
                testing.expectEqual(ref.data, converted.data);
            }
        }
    }
}

pub const Bytes = struct {
    data: []u8,
    allocator: ?*std.mem.Allocator = null,

    pub const wire_type = WireType.LengthDelimited;

    pub fn encodeInto(self: Bytes, buffer: []u8) []u8 {
        const header = (Uint64{ .data = self.data.len }).encodeInto(buffer);
        // TODO: use a generator instead of buffer overflow
        std.mem.copy(u8, buffer[header.len..], self.data);
        return buffer[0 .. header.len + self.data.len];
    }

    pub fn decode(raw: []const u8, len: *usize, allocator: *std.mem.Allocator) !Bytes {
        var header_len: usize = undefined;
        const header = try Uint64.decode(raw, &header_len);

        var data = try allocator.alloc(u8, header.data);
        errdefer allocator.free(data);

        std.mem.copy(u8, data, raw[header_len .. header_len + data.len]);
        len.* = header_len + data.len;

        return Bytes{
            .data = data,
            .allocator = allocator,
        };
    }
};

pub const String = struct {
    data: []u8,
    allocator: ?*std.mem.Allocator = null,

    pub const wire_type = WireType.LengthDelimited;

    pub fn encodeInto(self: String, buffer: []u8) []u8 {
        return (Bytes{ .data = self.data }).encodeInto(buffer);
    }

    pub fn decode(raw: []const u8, len: *usize, allocator: *std.mem.Allocator) !Bytes {
        var bytes = try Bytes.decode(raw, len, allocator);
        // TODO: validate unicode
        return String{
            .data = bytes.data,
            .allocator = bytes.allocator,
        };
    }
};

test "Bytes/String" {
    var buffer: [1000]u8 = undefined;
    var raw = "testing";

    var bytes = Bytes{ .data = raw[0..] };
    testing.expectEqualSlices(
        u8,
        [_]u8{ 0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67 },
        bytes.encodeInto(buffer[0..]),
    );

    @"fuzz": {
        var rng = std.rand.DefaultPrng.init(0);

        inline for ([_]type{ Bytes, String }) |T| {
            const data_type = fieldType(T, "data");

            var i = usize(0);
            while (i < 100) : (i += 1) {
                var len: usize = undefined;
                var encode_buf: [1000]u8 = undefined;
                var data_buf: [500]u8 = undefined;
                rng.random.bytes(data_buf[0..]);

                const ref = T{ .data = data_buf[0..] };
                const encoded_slice = ref.encodeInto(encode_buf[0..]);
                const converted = try T.decode(encoded_slice, &len, std.heap.direct_allocator);
                testing.expectEqualSlices(u8, ref.data, converted.data);
            }
        }
    }
}
