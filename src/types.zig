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
        const uint = try Vuint.decode(bytes, len);
        return Int64{ .data = @bitCast(i64, uint.data) };
    }
};

pub const Sint64 = struct {
    data: i64,

    pub const wire_type = WireType.Varint;

    pub fn encodeInto(self: Sint64, buffer: []u8) []u8 {
        const uint = Uint64{ .data = @intCast(u64, (self.data << 1) ^ (self.data >> 63)) };
        return uint.encodeInto(buffer);
    }

    pub fn decode(bytes: []const u8, len: *usize) !Int64 {
        const uint = try Uint64.decode(bytes, len);
        const raw = @intCast(i64, uint.data >> 1);
        return Int64{ .data = if (@mod(uint.data, 2) == 0) raw else -(raw + 1) };
    }
};

test "*int64" {
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
}
