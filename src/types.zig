const std = @import("std");
const testing = std.testing;

pub const Uint64 = struct {
    data: u64,

    pub fn encodeInto(self: Uint64, buffer: []u8) []u8 {
        var i = usize(0);
        var value = self.data;
        while (value > 0) : (i += 1) {
            buffer[i] = u8(0x80) + @truncate(u7, value);
            value >>= 7;
        }
        buffer[i - 1] = buffer[i - 1] & 0x7F;
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

    //    vint = Varint64.initInt(-1);
    //    testing.expectEqual(u64(std.math.maxInt(u64)), vint.uint);
    //    testing.expectEqual(i64(-1), vint.int());
    //
    //    vint = Varint64.initSint(-1);
    //    testing.expectEqual(u64(1), vint.uint);
    //    testing.expectEqual(i64(-1), vint.sint());
    //
    //    vint = Varint64.initSint(2147483647);
    //    testing.expectEqual(u64(4294967294), vint.uint);
    //    testing.expectEqual(i64(2147483647), vint.sint());
    //
    //    vint = Varint64.initSint(-2147483648);
    //    testing.expectEqual(u64(4294967295), vint.uint);
    //    testing.expectEqual(i64(-2147483648), vint.sint());
}
