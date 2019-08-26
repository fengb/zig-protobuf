const std = @import("std");
const testing = std.testing;

pub const ParseError = error{
    Overflow,
    EndOfStream,
    OutOfMemory,
};

pub const Uint64Coder = struct {
    pub const primitive = u64;

    pub fn encodeSize(data: u64) usize {
        const bits = u64.bit_count - @clz(u64, data);
        return std.math.max(divCeil(u64, bits, 7), 1);
    }

    pub fn encodeInto(out_stream: var, data: u64) !void {
        var value = data;
        while (value >= 0x80) : (value >>= 7) {
            try out_stream.writeByte(u8(0x80) + @truncate(u7, value));
        }
        try out_stream.writeByte(@truncate(u7, value));
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!u64 {
        var value = u64(0);

        for (bytes) |byte, i| {
            if (i >= 10) {
                return error.Overflow;
            }
            value += @intCast(u64, 0x7F & byte) << (7 * @intCast(u6, i));
            if (byte & 0x80 == 0) {
                len.* = i + 1;
                return value;
            }
        }
        // TODO: stream in bytes
        return error.EndOfStream;
    }
};

test "Uint64Coder" {
    var len: usize = 0;

    var uint = try Uint64Coder.decode([_]u8{1}, &len);
    testing.expectEqual(u64(1), uint);

    uint = try Uint64Coder.decode([_]u8{ 0b10101100, 0b00000010 }, &len);
    testing.expectEqual(u64(300), uint);

    uint = try Uint64Coder.decode([_]u8{ 0b10010110, 0b00000001 }, &len);
    testing.expectEqual(u64(150), uint);
}

pub const Int64Coder = struct {
    pub const primitive = i64;

    pub fn encodeSize(data: i64) usize {
        return Uint64Coder.encodeSize(@bitCast(u64, data));
    }

    pub fn encodeInto(out_stream: var, data: i64) !void {
        try Uint64Coder.encodeInto(out_stream, @bitCast(u64, data));
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!i64 {
        return @bitCast(i64, try Uint64Coder.decode(bytes, len));
    }
};

test "Int64Coder" {
    var buf1: [1000]u8 = undefined;
    var buf2: [1000]u8 = undefined;
    var out1 = std.io.SliceOutStream.init(buf1[0..]);
    var out2 = std.io.SliceOutStream.init(buf2[0..]);

    try Uint64Coder.encodeInto(&out1.stream, std.math.maxInt(u64));
    try Int64Coder.encodeInto(&out2.stream, -1);
    testing.expectEqualSlices(u8, out1.getWritten(), out2.getWritten());
}

pub const Sint64Coder = struct {
    pub const primitive = i64;

    pub fn encodeSize(data: i64) usize {
        return Uint64Coder.encodeSize(@bitCast(u64, (data << 1) ^ (data >> 63)));
    }

    pub fn encodeInto(out_stream: var, data: i64) !void {
        try Uint64Coder.encodeInto(out_stream, @bitCast(u64, (data << 1) ^ (data >> 63)));
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!i64 {
        const source = try Uint64Coder.decode(bytes, len);
        const raw = @bitCast(i64, source >> 1);
        return if (@mod(source, 2) == 0) raw else -(raw + 1);
    }
};

test "Sint64Coder" {
    var buf1: [1000]u8 = undefined;
    var buf2: [1000]u8 = undefined;
    var out1 = std.io.SliceOutStream.init(buf1[0..]);
    var out2 = std.io.SliceOutStream.init(buf2[0..]);

    try Uint64Coder.encodeInto(&out1.stream, 1);
    try Sint64Coder.encodeInto(&out2.stream, -1);
    testing.expectEqualSlices(u8, out1.getWritten(), out2.getWritten());

    out1.reset();
    out2.reset();
    try Uint64Coder.encodeInto(&out1.stream, 4294967294);
    try Sint64Coder.encodeInto(&out2.stream, 2147483647);
    testing.expectEqualSlices(u8, out1.getWritten(), out2.getWritten());

    out1.reset();
    out2.reset();
    try Uint64Coder.encodeInto(&out1.stream, 4294967295);
    try Sint64Coder.encodeInto(&out2.stream, -2147483648);
    testing.expectEqualSlices(u8, out1.getWritten(), out2.getWritten());
}

pub const Fixed64Coder = struct {
    pub const primitive = u64;

    pub fn encodeSize(data: u64) usize {
        return 8;
    }

    pub fn encodeInto(out_stream: var, data: u64) !void {
        var buffer = [_]u8{0} ** 8;
        std.mem.writeIntSliceLittle(u64, buffer[0..], data);
        try out_stream.write(buffer[0..]);
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!u64 {
        len.* = 8;
        return std.mem.readIntSliceLittle(u64, bytes);
    }
};

pub const Fixed32Coder = struct {
    pub const primitive = u32;

    pub fn encodeSize(data: u32) usize {
        return 4;
    }

    pub fn encodeInto(out_stream: var, data: u32) !void {
        var buffer = [_]u8{0} ** 4;
        std.mem.writeIntSliceLittle(u32, buffer[0..], data);
        try out_stream.write(buffer[0..]);
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!u32 {
        len.* = 4;
        return std.mem.readIntSliceLittle(u32, bytes);
    }
};

pub const BytesCoder = struct {
    pub fn encodeSize(data: []const u8) usize {
        const header_size = Uint64Coder.encodeSize(data.len);
        return header_size + data.len;
    }

    pub fn encodeInto(out_stream: var, data: []const u8) !void {
        try Uint64Coder.encodeInto(out_stream, data.len);
        try out_stream.write(data);
    }

    pub fn decode(buffer: []const u8, len: *usize, allocator: *std.mem.Allocator) ![]u8 {
        var header_len: usize = undefined;
        const header = try Uint64Coder.decode(buffer, &header_len);

        var data = try allocator.alloc(u8, header);
        errdefer allocator.free(data);

        std.mem.copy(u8, data, buffer[header_len .. header_len + data.len]);
        len.* = header_len + data.len;

        return data;
    }
};

test "BytesCoder" {
    var buf: [1000]u8 = undefined;
    var out = std.io.SliceOutStream.init(buf[0..]);
    try BytesCoder.encodeInto(&out.stream, "testing");

    testing.expectEqualSlices(
        u8,
        [_]u8{ 0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67 },
        out.getWritten(),
    );
}

fn divCeil(comptime T: type, numerator: T, denominator: T) T {
    return (numerator + denominator - 1) / denominator;
}
