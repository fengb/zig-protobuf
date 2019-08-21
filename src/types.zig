const std = @import("std");
const coder = @import("coder.zig");
const testing = std.testing;

const ParseError = coder.ParseError;

const WireType = enum(u3) {
    Varint = 0,
    _64bit = 1,
    LengthDelimited = 2,
    StartGroup = 3,
    EndGroup = 4,
    _32bit = 5,
};

pub const FieldInfo = struct {
    wire_type: WireType,
    number: u61,

    pub fn init(value: u64) FieldInfo {
        return FieldInfo{
            .wire_type = @intToEnum(WireType, @truncate(u3, value)),
            .number = @intCast(u61, value >> 3),
        };
    }

    pub fn encodeInto(self: FieldInfo, buffer: []u8) []u8 {
        const uint = (@intCast(u64, self.number) << 3) + @enumToInt(self.wire_type);
        return coder.Uint64Coder.encode(buffer, uint);
    }

    pub fn decode(buffer: []const u8, len: *usize) ParseError!FieldInfo {
        const raw = try coder.Uint64Coder.decode(buffer, len);
        return init(raw);
    }
};

test "FieldInfo" {
    const field = FieldInfo.init(8);
    testing.expectEqual(WireType.Varint, field.wire_type);
    testing.expectEqual(u61(1), field.number);
}

pub fn Uint64(comptime number: u63) type {
    return FromVarintCast(u64, coder.Uint64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Uint32(comptime number: u63) type {
    return FromVarintCast(u32, coder.Uint64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Int64(comptime number: u63) type {
    return FromVarintCast(i64, coder.Int64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Int32(comptime number: u63) type {
    return FromVarintCast(i32, coder.Int64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Sint64(comptime number: u63) type {
    return FromVarintCast(i64, coder.Sint64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Sint32(comptime number: u63) type {
    return FromVarintCast(i32, coder.Sint64Coder, FieldInfo{
        .wire_type = .Varint,
        .number = number,
    });
}

fn FromBitCast(comptime TargetPrimitive: type, comptime Coder: type, comptime info: FieldInfo) type {
    return struct {
        const Self = @This();

        data: TargetPrimitive,

        pub const default = 0;
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

fn FromVarintCast(comptime TargetPrimitive: type, comptime Coder: type, comptime info: FieldInfo) type {
    return struct {
        const Self = @This();

        data: TargetPrimitive,

        pub const default = 0;
        pub const field_info = info;

        pub fn encodeSize(self: Self) usize {
            return Coder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return Coder.encode(buffer, self.data);
        }

        pub fn decode(bytes: []const u8, len: *usize) ParseError!Self {
            const raw = try Coder.decode(bytes, len);
            return Self{ .data = @intCast(TargetPrimitive, raw) };
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
    inline for ([_]type{ Uint64(1), Int64(1), Sint64(1), Uint32(1), Int32(1), Sint32(1) }) |T| {
        const data_field = std.meta.fieldInfo(T, "data");

        var i = usize(0);
        while (i < 100) : (i += 1) {
            const base = T{ .data = rng.random.int(data_field.field_type) };
            try testEncodeDecode(T, base);
        }
    }
}

pub fn Fixed64(comptime number: u63) type {
    return FromBitCast(u64, coder.Fixed64Coder, FieldInfo{
        .wire_type = ._64bit,
        .number = number,
    });
}
pub fn Sfixed64(comptime number: u63) type {
    return FromBitCast(i64, coder.Fixed64Coder, FieldInfo{
        .wire_type = ._64bit,
        .number = number,
    });
}
pub fn Fixed32(comptime number: u63) type {
    return FromBitCast(u32, coder.Fixed32Coder, FieldInfo{
        .wire_type = ._32bit,
        .number = number,
    });
}
pub fn Sfixed32(comptime number: u63) type {
    return FromBitCast(i32, coder.Fixed32Coder, FieldInfo{
        .wire_type = ._32bit,
        .number = number,
    });
}
pub fn Double(comptime number: u63) type {
    return FromBitCast(f64, coder.Fixed64Coder, FieldInfo{
        .wire_type = ._64bit,
        .number = number,
    });
}
pub fn Float(comptime number: u63) type {
    return FromBitCast(f32, coder.Fixed32Coder, FieldInfo{
        .wire_type = ._32bit,
        .number = number,
    });
}

test "Fixed numbers" {
    inline for ([_]type{ Fixed64(1), Fixed32(1), Sfixed64(1), Sfixed32(1) }) |T| {
        const data_field = std.meta.fieldInfo(T, "data");

        var i = usize(0);
        while (i < 100) : (i += 1) {
            const base = T{ .data = rng.random.int(data_field.field_type) };
            try testEncodeDecode(T, base);
        }
    }

    inline for ([_]type{ Double(1), Float(1) }) |T| {
        const data_field = std.meta.fieldInfo(T, "data");

        var i = usize(0);
        while (i < 100) : (i += 1) {
            const base = T{ .data = rng.random.float(data_field.field_type) };
            try testEncodeDecode(T, base);
        }
    }
}

pub fn Bytes(comptime number: u63) type {
    return struct {
        const Self = @This();

        data: []u8,
        allocator: ?*std.mem.Allocator = null,

        pub const default = [_]u8{};
        pub const field_info = FieldInfo{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return coder.BytesCoder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return coder.BytesCoder.encode(buffer, self.data);
        }

        pub fn decode(buffer: []const u8, len: *usize, allocator: *std.mem.Allocator) !Self {
            return Self{
                .data = try coder.BytesCoder.decode(buffer, len, allocator),
                .allocator = allocator,
            };
        }
    };
}

pub fn String(comptime number: u63) type {
    return struct {
        const Self = @This();

        data: []u8,
        allocator: ?*std.mem.Allocator = null,

        pub const default = [_]u8{};
        pub const field_info = FieldInfo{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return coder.BytesCoder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, buffer: []u8) []u8 {
            return coder.BytesCoder.encode(buffer, self.data);
        }

        pub fn decode(buffer: []const u8, len: *usize, allocator: *std.mem.Allocator) !Self {
            // TODO: validate unicode
            return Self{
                .data = try coder.BytesCoder.decode(buffer, len, allocator),
                .allocator = allocator,
            };
        }
    };
}

test "Bytes/String" {
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

pub fn Bool(comptime number: u63) type {
    return struct {
        const Self = @This();

        data: bool,

        pub const default = false;
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
            const raw = try coder.Uint64Coder.decode(bytes, len);
            // TODO: verify that bools *must* be 0 or 1
            if (raw > 1) {
                return error.Overflow;
            }
            return Self{ .data = if (raw == 0) false else true };
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

pub fn Repeated(comptime number: u63, comptime Tfn: var) type {
    const T = Tfn(number);

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
    var repeated_field = Repeated(1, Fixed32){};
    repeated_field.initDecoder(std.heap.direct_allocator);
    var len: usize = undefined;
    try repeated_field.decodeOne(twelve[0..], &len);
    try repeated_field.decodeOne(hundred[0..], &len);
    testing.expectEqualSlices(u32, [_]u32{ 12, 100 }, repeated_field._decoder.?.toSlice());
}
