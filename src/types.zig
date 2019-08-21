const std = @import("std");
const testing = std.testing;

const ParseError = error{
    Overflow,
    EndOfStream,
    OutOfMemory,
};

pub const WireType = enum(u3) {
    Varint = 0,
    _64bit = 1,
    LengthDelimited = 2,
    StartGroup = 3,
    EndGroup = 4,
    _32bit = 5,
};

const FieldInfo = struct {
    wire_type: WireType,
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
fn divCeil(comptime T: type, numerator: T, denominator: T) T {
    return (numerator + denominator - 1) / denominator;
}

pub fn Uint64_(comptime number: comptime_int) type {
    return FromBitCast_(u64, Uint64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

pub const Uint64 = struct {
    data: u64 = 0,

    pub const wire_type = WireType.Varint;

    pub fn encodeSize(self: Uint64) usize {
        const bits = u64.bit_count - @clz(u64, self.data);
        return std.math.max(divCeil(u64, bits, 7), 1);
    }

    pub fn encodeInto(self: Uint64, buffer: []u8) []u8 {
        if (self.data == 0) {
            buffer[0] = 0;
            return buffer[0..1];
        }
        var i = usize(0);
        var value = self.data;
        while (value > 0) : (i += 1) {
            buffer[i] = u8(0x80) + @truncate(u7, value);
            value >>= 7;
        }
        buffer[i - 1] &= 0x7F;
        return buffer[0..i];
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!Uint64 {
        var value = u64(0);

        for (bytes) |byte, i| {
            if (i >= 10) {
                return error.Overflow;
            }
            value += @intCast(u64, 0x7F & byte) << (7 * @intCast(u6, i));
            if (byte & 0x80 == 0) {
                len.* = i + 1;
                return Uint64{ .data = value };
            }
        }
        // TODO: stream in bytes
        return error.EndOfStream;
    }
};

const Uint64Coder = struct {
    const primitive = u64;

    pub fn encodeSize(data: u64) usize {
        const bits = u64.bit_count - @clz(u64, data);
        return std.math.max(divCeil(u64, bits, 7), 1);
    }

    pub fn encode(buffer: []u8, data: u64) []u8 {
        if (data == 0) {
            buffer[0] = 0;
            return buffer[0..1];
        }
        var i = usize(0);
        var value = data;
        while (value > 0) : (i += 1) {
            buffer[i] = u8(0x80) + @truncate(u7, value);
            value >>= 7;
        }
        buffer[i - 1] &= 0x7F;
        return buffer[0..i];
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
pub fn Int64(comptime number: comptime_int) type {
    return FromBitCast_(i64, Uint64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

fn FromBitCast_(comptime TargetPrimitive: type, comptime Coder: type, comptime info: FieldInfo) type {
    return struct {
        const Self = @This();

        data: TargetPrimitive = 0,

        pub const field_info = info;

        pub fn encodeSize(self: Self) usize {
            return Coder.encodeSize(@bitCast(Coder.primitive, self.data));
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return Coder.encode(buffer, @bitCast(Coder.primitive, self.data));
        }

        pub fn decode(buffer: []const u8, len: *usize) ParseError!Self {
            const raw = try Coder.decode(buffer, len);
            return Self{ .data = @bitCast(TargetPrimitive, raw) };
        }
    };
}

fn FromBitCast(comptime TargetPrimitive: type, comptime SourceType: type) type {
    return struct {
        data: TargetPrimitive = 0,

        const Self = @This();

        pub const wire_type = WireType.Varint;

        pub fn encodeSize(self: Self) usize {
            const source = SourceType{ .data = @bitCast(TargetPrimitive, self.data) };
            return source.encodeSize();
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            const source = SourceType{ .data = @bitCast(TargetPrimitive, self.data) };
            return source.encodeInto(buffer);
        }

        pub fn decode(bytes: []const u8, len: *usize) ParseError!Self {
            const source = try SourceType.decode(bytes, len);
            return Self{ .data = @bitCast(TargetPrimitive, source.data) };
        }
    };
}

pub const Sint64 = struct {
    data: i64 = 0,

    pub const wire_type = WireType.Varint;

    pub fn encodeSize(self: Sint64) usize {
        const source = Uint64{ .data = @bitCast(u64, (self.data << 1) ^ (self.data >> 63)) };
        return source.encodeSize();
    }

    pub fn encodeInto(self: Sint64, buffer: []u8) []u8 {
        const source = Uint64{ .data = @bitCast(u64, (self.data << 1) ^ (self.data >> 63)) };
        return source.encodeInto(buffer);
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!Sint64 {
        const source = try Uint64.decode(bytes, len);
        const raw = @bitCast(i64, source.data >> 1);
        return Sint64{ .data = if (@mod(source.data, 2) == 0) raw else -(raw + 1) };
    }
};

pub const Uint32 = FromIntCast(u32, Uint64);
//pub const Int32 = FromIntCast(i32, Int64);
pub const Sint32 = FromIntCast(i32, Sint64);

fn FromIntCast(comptime TargetPrimitive: type, comptime SourceType: type) type {
    return struct {
        const Self = @This();

        data: TargetPrimitive = 0,

        pub const wire_type = WireType.Varint;

        pub fn encodeSize(self: Self) usize {
            const source = SourceType{ .data = self.data };
            return source.encodeSize();
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return (SourceType{ .data = self.data }).encodeInto(buffer);
        }

        pub fn decode(bytes: []const u8, len: *usize) ParseError!Self {
            const source = try SourceType.decode(bytes, len);
            return Self{ .data = @intCast(TargetPrimitive, source.data) };
        }
    };
}

var rng = std.rand.DefaultPrng.init(0);
fn testEncodeDecode(comptime T: type, base: T) !void {
    var decoded_len: usize = undefined;
    var buf: [1000]u8 = undefined;

    const encoded_slice = base.encodeInto(buf[0..]);
    testing.expectEqual(base.encodeSize(), encoded_slice.len);
    const decoded = try T.decode(encoded_slice, &decoded_len);
    testing.expectEqual(base.data, decoded.data);
    testing.expectEqual(base.encodeSize(), decoded_len);
}

fn testEncodeDecodeSlices(comptime T: type, base: T) !void {
    var decoded_len: usize = undefined;
    var buf: [1000]u8 = undefined;

    const encoded_slice = base.encodeInto(buf[0..]);
    testing.expectEqual(base.encodeSize(), encoded_slice.len);
    const decoded = try T.decode(encoded_slice, &decoded_len, std.heap.direct_allocator);
    testing.expectEqualSlices(u8, base.data, decoded.data);
    testing.expectEqual(base.encodeSize(), decoded_len);
}

test "Var int" {
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
        (Int64(1){ .data = -1 }).encodeInto(buf1[0..]),
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
        //inline for ([_]type{ Uint64, Int64(1), Sint64, Uint32, Int32, Sint32 }) |T| {
        inline for ([_]type{ Uint64_(1), Int64(1), Sint64, Uint32, Sint32 }) |T| {
            const data_field = std.meta.fieldInfo(T, "data");

            var i = usize(0);
            while (i < 100) : (i += 1) {
                const base = T{ .data = rng.random.int(data_field.field_type) };
                try testEncodeDecode(T, base);
            }
        }
    }
}

pub const Fixed64 = struct {
    data: u64 = 0,

    pub const wire_type = WireType._64bit;

    pub fn encodeSize(self: Fixed64) usize {
        return 8;
    }

    pub fn encodeInto(self: Fixed64, buffer: []u8) []u8 {
        var result = buffer[0..self.encodeSize()];
        std.mem.writeIntSliceLittle(u64, result, self.data);
        return result;
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!Fixed64 {
        len.* = 8;
        return Fixed64{ .data = std.mem.readIntSliceLittle(u64, bytes) };
    }
};

pub const Fixed32 = struct {
    data: u32 = 0,

    pub const wire_type = WireType._32bit;

    pub fn encodeSize(self: Fixed32) usize {
        return 4;
    }

    pub fn encodeInto(self: Fixed32, buffer: []u8) []u8 {
        var result = buffer[0..self.encodeSize()];
        std.mem.writeIntSliceLittle(u32, result, self.data);
        return result;
    }

    pub fn decode(bytes: []const u8, len: *usize) ParseError!Fixed32 {
        len.* = 4;
        return Fixed32{ .data = std.mem.readIntSliceLittle(u32, bytes) };
    }
};

pub const Sfixed64 = FromBitCast(i64, Fixed64);
pub const Sfixed32 = FromBitCast(i32, Fixed32);
pub const Double = FromBitCast(f64, Fixed64);
pub const Float = FromBitCast(f32, Fixed32);

test "Fixed numbers" {
    @"fuzz": {
        inline for ([_]type{ Fixed64, Fixed32, Sfixed64, Sfixed32 }) |T| {
            const data_field = std.meta.fieldInfo(T, "data");

            var i = usize(0);
            while (i < 100) : (i += 1) {
                const base = T{ .data = rng.random.int(data_field.field_type) };
                try testEncodeDecode(T, base);
            }
        }

        inline for ([_]type{ Double, Float }) |T| {
            const data_field = std.meta.fieldInfo(T, "data");

            var i = usize(0);
            while (i < 100) : (i += 1) {
                const base = T{ .data = rng.random.float(data_field.field_type) };
                try testEncodeDecode(T, base);
            }
        }
    }
}

pub fn Bytes(comptime number: comptime_int) type {
    return struct {
        const Self = @This();

        data: []u8 = [_]u8{},
        allocator: ?*std.mem.Allocator = null,

        pub const field_info = FieldInfo{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return BytesCoder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return BytesCoder.encode(buffer, self.data);
        }

        pub fn decode(buffer: []const u8, len: *usize, allocator: *std.mem.Allocator) !Self {
            return Self{
                .data = try BytesCoder.decode(buffer, len, allocator),
                .allocator = allocator,
            };
        }
    };
}

pub fn String(comptime number: comptime_int) type {
    return struct {
        const Self = @This();

        data: []u8 = [_]u8{},
        allocator: ?*std.mem.Allocator = null,

        pub const field_info = FieldInfo{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return BytesCoder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return BytesCoder.encode(buffer, self.data);
        }

        pub fn decode(buffer: []const u8, len: *usize, allocator: *std.mem.Allocator) !Self {
            // TODO: validate unicode
            return Self{
                .data = try BytesCoder.decode(buffer, len, allocator),
                .allocator = allocator,
            };
        }
    };
}

const BytesCoder = struct {
    pub fn encodeSize(data: []u8) usize {
        const header_size = (Uint64{ .data = data.len }).encodeSize();
        return header_size + data.len;
    }

    pub fn encode(buffer: []u8, data: []u8) []u8 {
        const header = (Uint64{ .data = data.len }).encodeInto(buffer);
        // TODO: use a generator instead of buffer overflow
        std.mem.copy(u8, buffer[header.len..], data);
        return buffer[0 .. header.len + data.len];
    }

    pub fn decode(buffer: []const u8, len: *usize, allocator: *std.mem.Allocator) ![]u8 {
        var header_len: usize = undefined;
        const header = try Uint64.decode(buffer, &header_len);

        var data = try allocator.alloc(u8, header.data);
        errdefer allocator.free(data);

        std.mem.copy(u8, data, buffer[header_len .. header_len + data.len]);
        len.* = header_len + data.len;

        return data;
    }
};

test "Bytes/String" {
    var buffer: [1000]u8 = undefined;
    var raw = "testing";

    var bytes = Bytes(1){ .data = raw[0..] };
    testing.expectEqualSlices(
        u8,
        [_]u8{ 0x07, 0x74, 0x65, 0x73, 0x74, 0x69, 0x6e, 0x67 },
        bytes.encodeInto(buffer[0..]),
    );

    @"fuzz": {
        inline for ([_]type{ Bytes(1), String(1) }) |T| {
            var i = usize(0);
            while (i < 100) : (i += 1) {
                var base_buf: [500]u8 = undefined;
                rng.random.bytes(base_buf[0..]);

                const base = T{ .data = base_buf[0..] };
                try testEncodeDecodeSlices(T, base);
            }
        }
    }
}

pub fn Bool(comptime number: comptime_int) type {
    return struct {
        const Self = @This();

        data: bool = false,

        pub const field_info = FieldInfo{
            .wire_type = .Varint,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return 1;
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            buffer[0] = if (self.data) u8(1) else 0;
            return buffer[0..1];
        }

        pub fn decode(bytes: []const u8, len: *usize) ParseError!Self {
            const source = try Uint64.decode(bytes, len);
            // TODO: verify that bools *must* be 0 or 1
            if (source.data > 1) {
                return error.Overflow;
            }
            return Self{ .data = if (source.data == 0) false else true };
        }
    };
}

test "Bool" {
    @"fuzz": {
        inline for ([_]bool{ false, true }) |b| {
            const base = Bool(1){ .data = b };
            try testEncodeDecode(Bool(1), base);
        }
    }
}

pub fn Repeated(comptime T: type) type {
    std.debug.assert(@hasField(T, "data"));
    std.debug.assert(@hasDecl(T, "encodeSize"));
    std.debug.assert(@hasDecl(T, "encodeInto"));
    std.debug.assert(@hasDecl(T, "decode"));

    const DataType = std.meta.fieldInfo(T, "data").field_type;

    return struct {
        const Self = @This();

        data: []DataType = [_]DataType{},
        allocator: ?*std.mem.Allocator = null,
        _decoder: ?std.ArrayList(DataType) = null,

        fn initDecoder(self: *Self, allocator: *std.mem.Allocator) void {
            std.debug.assert(self.data.len == 0);
            self._decoder = std.ArrayList(DataType).init(allocator);
        }

        pub fn encodeSize(self: Self) usize {
            var sum = usize(0);
            for (self.data) |item| {
                const wrapper = DataType{ .data = item };
                sum += wrapper.encodeSize();
            }
            return sum;
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            var cursor = usize(0);
            for (self.data) |item| {
                const wrapper = DataType{ .data = item };
                const result = wrapper.encodeInto(buffer[cursor..]);
                cursor += result.len;
            }
            return buffer[0..cursor];
        }

        pub fn decodeOne(self: *Self, raw: []const u8, len: *usize) ParseError!void {
            std.debug.assert(self._decoder != null);
            const base = try T.decode(raw, len);
            try self._decoder.?.append(base.data);
        }

        pub fn decodePacked(self: *Self, raw: []const u8, len: *usize) ParseError!void {
            std.debug.assert(self._decoder != null);
            var header_len: usize = undefined;
            const header = try Uint64.decode(raw, &header_len);

            var items_len = usize(0);
            while (items_len < header.data) {
                var len: usize = undefined;
                try self.decodeOne(raw[header_len + items_len ..], &len);
                items_len += len;
            }

            if (items_len > header.data) {
                // Header listed length != items actual length
                return error.Overflow;
            }

            len.* = header_len + items_len;
        }
    };
}

test "Repeated" {
    const twelve = [_]u8{ 12, 0, 0, 0 };
    const hundred = [_]u8{ 100, 0, 0, 0 };
    var repeated_field = Repeated(Fixed32){};
    repeated_field.initDecoder(std.heap.direct_allocator);
    var len: usize = undefined;
    try repeated_field.decodeOne(twelve[0..], &len);
    try repeated_field.decodeOne(hundred[0..], &len);
    testing.expectEqualSlices(u32, [_]u32{ 12, 100 }, repeated_field._decoder.?.toSlice());
}
