const std = @import("std");
const coder = @import("coder.zig");
const testing = std.testing;

const WireType = enum(u3) {
    Varint = 0,
    _64bit = 1,
    LengthDelimited = 2,
    StartGroup = 3,
    EndGroup = 4,
    _32bit = 5,
};

pub const FieldMeta = struct {
    wire_type: WireType,
    number: u61,

    pub fn init(value: u64) FieldMeta {
        return FieldMeta{
            .wire_type = @intToEnum(WireType, @truncate(u3, value)),
            .number = @intCast(u61, value >> 3),
        };
    }

    pub fn encodeInto(self: FieldMeta, out_stream: var) !void {
        const uint = (@intCast(u64, self.number) << 3) + @enumToInt(self.wire_type);
        try coder.Uint64Coder.encodeInto(out_stream, uint);
    }

    pub fn decode(in_stream: var) !FieldMeta {
        const raw = try coder.Uint64Coder.decodeFrom(in_stream);
        return init(raw);
    }
};

test "FieldMeta" {
    const field = FieldMeta.init(8);
    testing.expectEqual(WireType.Varint, field.wire_type);
    testing.expectEqual(u61(1), field.number);
}

pub fn Uint64(comptime number: u63) type {
    return FromVarintCast(u64, coder.Uint64Coder, FieldMeta{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Uint32(comptime number: u63) type {
    return FromVarintCast(u32, coder.Uint64Coder, FieldMeta{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Int64(comptime number: u63) type {
    return FromVarintCast(i64, coder.Int64Coder, FieldMeta{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Int32(comptime number: u63) type {
    return FromVarintCast(i32, coder.Int64Coder, FieldMeta{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Sint64(comptime number: u63) type {
    return FromVarintCast(i64, coder.Sint64Coder, FieldMeta{
        .wire_type = .Varint,
        .number = number,
    });
}

pub fn Sint32(comptime number: u63) type {
    return FromVarintCast(i32, coder.Sint64Coder, FieldMeta{
        .wire_type = .Varint,
        .number = number,
    });
}

fn FromBitCast(comptime TargetPrimitive: type, comptime Coder: type, comptime info: FieldMeta) type {
    return struct {
        const Self = @This();

        value: TargetPrimitive = 0,

        pub const field_meta = info;

        pub fn encodeSize(self: Self) usize {
            return Coder.encodeSize(@bitCast(Coder.primitive, self.value));
        }

        pub fn encodeInto(self: Self, out_stream: var) !void {
            try Coder.encodeInto(out_stream, @bitCast(Coder.primitive, self.value));
        }

        pub fn decodeFrom(self: *Self, in_stream: var) !void {
            const raw = try Coder.decodeFrom(in_stream);
            self.value = @bitCast(TargetPrimitive, raw);
        }
    };
}

fn FromVarintCast(comptime TargetPrimitive: type, comptime Coder: type, comptime info: FieldMeta) type {
    return struct {
        const Self = @This();

        value: TargetPrimitive = 0,

        pub const field_meta = info;

        pub fn encodeSize(self: Self) usize {
            return Coder.encodeSize(self.value);
        }

        pub fn encodeInto(self: Self, out_stream: var) !void {
            try Coder.encodeInto(out_stream, self.value);
        }

        pub fn decodeFrom(self: *Self, in_stream: var) !void {
            const raw = try Coder.decodeFrom(in_stream);
            self.value = @intCast(TargetPrimitive, raw);
        }
    };
}

var rng = std.rand.DefaultPrng.init(0);
fn testEncodeDecode(comptime T: type, base: T) !void {
    var buffer: [1000]u8 = undefined;

    var out = std.io.SliceOutStream.init(buffer[0..]);

    try base.encodeInto(&out.stream);
    testing.expectEqual(base.encodeSize(), out.getWritten().len);

    var mem_in = std.io.SliceInStream.init(out.getWritten());
    var decoded: T = undefined;
    const decoded_len = try decoded.decodeFrom(&mem_in.stream);
    testing.expectEqual(base.value, decoded.value);
    testing.expectEqual(base.encodeSize(), mem_in.pos);
}

fn testEncodeDecodeSlices(comptime T: type, base: T) !void {
    var buffer: [1000]u8 = undefined;

    var out = std.io.SliceOutStream.init(buffer[0..]);

    try base.encodeInto(&out.stream);
    testing.expectEqual(base.encodeSize(), out.getWritten().len);

    var mem_in = std.io.SliceInStream.init(out.getWritten());
    var decoded: T = undefined;
    try decoded.decodeFromAlloc(&mem_in.stream, std.heap.direct_allocator);
    testing.expectEqualSlices(u8, base.value, decoded.value);
    testing.expectEqual(base.encodeSize(), mem_in.pos);
}

test "Var int" {
    inline for ([_]type{ Uint64(1), Int64(1), Sint64(1), Uint32(1), Int32(1), Sint32(1) }) |T| {
        const value_field = std.meta.fieldInfo(T, "value");

        var i = usize(0);
        while (i < 100) : (i += 1) {
            const base = T{ .value = rng.random.int(value_field.field_type) };
            try testEncodeDecode(T, base);
        }
    }
}

pub fn Fixed64(comptime number: u63) type {
    return FromBitCast(u64, coder.Fixed64Coder, FieldMeta{
        .wire_type = ._64bit,
        .number = number,
    });
}
pub fn Sfixed64(comptime number: u63) type {
    return FromBitCast(i64, coder.Fixed64Coder, FieldMeta{
        .wire_type = ._64bit,
        .number = number,
    });
}
pub fn Fixed32(comptime number: u63) type {
    return FromBitCast(u32, coder.Fixed32Coder, FieldMeta{
        .wire_type = ._32bit,
        .number = number,
    });
}
pub fn Sfixed32(comptime number: u63) type {
    return FromBitCast(i32, coder.Fixed32Coder, FieldMeta{
        .wire_type = ._32bit,
        .number = number,
    });
}
pub fn Double(comptime number: u63) type {
    return FromBitCast(f64, coder.Fixed64Coder, FieldMeta{
        .wire_type = ._64bit,
        .number = number,
    });
}
pub fn Float(comptime number: u63) type {
    return FromBitCast(f32, coder.Fixed32Coder, FieldMeta{
        .wire_type = ._32bit,
        .number = number,
    });
}

test "Fixed numbers" {
    inline for ([_]type{ Fixed64(1), Fixed32(1), Sfixed64(1), Sfixed32(1) }) |T| {
        const value_field = std.meta.fieldInfo(T, "value");

        var i = usize(0);
        while (i < 100) : (i += 1) {
            const base = T{ .value = rng.random.int(value_field.field_type) };
            try testEncodeDecode(T, base);
        }
    }

    inline for ([_]type{ Double(1), Float(1) }) |T| {
        const value_field = std.meta.fieldInfo(T, "value");

        var i = usize(0);
        while (i < 100) : (i += 1) {
            const base = T{ .value = rng.random.float(value_field.field_type) };
            try testEncodeDecode(T, base);
        }
    }
}

pub fn Bytes(comptime number: u63) type {
    return struct {
        const Self = @This();

        value: []u8 = [_]u8{},
        allocator: ?*std.mem.Allocator = null,

        pub const field_meta = FieldMeta{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn deinit(self: *Self) void {
            if (self.allocator) |alloc| {
                alloc.free(self.value);
                self.* = Self{};
            }
        }

        pub fn encodeSize(self: Self) usize {
            return coder.BytesCoder.encodeSize(self.value);
        }

        pub fn encodeInto(self: Self, out_stream: var) !void {
            try coder.BytesCoder.encodeInto(out_stream, self.value);
        }

        pub fn decodeFromAlloc(self: *Self, in_stream: var, allocator: *std.mem.Allocator) !void {
            self.value = try coder.BytesCoder.decodeFrom(in_stream, allocator);
            self.allocator = allocator;
        }
    };
}

pub fn String(comptime number: u63) type {
    return struct {
        const Self = @This();

        value: []const u8 = "",
        allocator: ?*std.mem.Allocator = null,

        pub const field_meta = FieldMeta{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn deinit(self: *Self) void {
            if (self.allocator) |alloc| {
                alloc.free(self.value);
                self.* = Self{};
            }
        }

        pub fn encodeSize(self: Self) usize {
            return coder.BytesCoder.encodeSize(self.value);
        }

        pub fn encodeInto(self: Self, out_stream: var) !void {
            try coder.BytesCoder.encodeInto(out_stream, self.value);
        }

        pub fn decodeFromAlloc(self: *Self, in_stream: var, allocator: *std.mem.Allocator) !void {
            // TODO: validate unicode
            self.value = try coder.BytesCoder.decodeFrom(in_stream, allocator);
            self.allocator = allocator;
        }
    };
}

test "Bytes/String" {
    inline for ([_]type{ Bytes(1), String(1) }) |T| {
        var i = usize(0);
        while (i < 100) : (i += 1) {
            var base_buf: [500]u8 = undefined;
            rng.random.bytes(base_buf[0..]);

            const base = T{ .value = base_buf[0..] };
            try testEncodeDecodeSlices(T, base);
        }
    }
}

pub fn Bool(comptime number: u63) type {
    return struct {
        const Self = @This();

        value: bool = false,

        pub const field_meta = FieldMeta{
            .wire_type = .Varint,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return 1;
        }

        pub fn encodeInto(self: Self, out_stream: var) !void {
            try out_stream.writeByte(if (self.value) u8(1) else 0);
        }

        pub fn decodeFrom(self: *Self, in_stream: var) !void {
            const raw = try in_stream.readByte();
            // TODO: verify that bools *must* be 0 or 1
            if (raw > 1) {
                return error.Overflow;
            }
            self.value = raw != 0;
        }
    };
}

test "Bool" {
    @"fuzz": {
        inline for ([_]bool{ false, true }) |b| {
            const base = Bool(1){ .value = b };
            try testEncodeDecode(Bool(1), base);
        }
    }
}

pub fn Repeated(comptime number: u63, comptime Tfn: var) type {
    const T = Tfn(number);

    std.debug.assert(@hasField(T, "value"));
    std.debug.assert(@hasDecl(T, "encodeSize"));
    std.debug.assert(@hasDecl(T, "encodeInto"));
    std.debug.assert(@hasDecl(T, "decodeFrom"));

    const ValueType = std.meta.fieldInfo(T, "value").field_type;

    return struct {
        const Self = @This();
        const List = std.ArrayList(ValueType);

        value: []ValueType = [_]ValueType{},
        allocator: ?*std.mem.Allocator = null,
        _decode_builder: ?List = null,

        pub fn deinit(self: *Self) void {
            if (self._decode_builder) |*decode_builder| {
                std.debug.assert(self.value.len == 0);
                decode_builder.deinit();
                self.* = Self{};
            } else if (self.allocator) |alloc| {
                alloc.free(self.value);
                self.* = Self{};
            }
        }

        pub fn encodeSize(self: Self) usize {
            var sum = usize(0);
            for (self.value) |item| {
                const wrapper = ValueType{ .value = item };
                sum += wrapper.encodeSize();
            }
            return sum;
        }

        pub fn encodeInto(self: Self, out_stream: var) !void {
            for (self.value) |item| {
                const wrapper = ValueType{ .value = item };
                wrapper.encodeInto(out_stream);
            }
        }

        pub fn decodeFromAlloc(self: *Self, in_stream: var, allocator: *std.mem.Allocator) !void {
            if (self._decode_builder == null) {
                self.deinit();
                self._decode_builder = List.init(allocator);
            }
            var base: T = undefined;
            try base.decodeFrom(in_stream);
            try self._decode_builder.?.append(base.value);
        }

        pub fn decodePacked(self: *Self, in_stream: var, allocator: *std.mem.Allocator) !usize {
            const header = try Uint64.decodeFrom(in_stream);

            var items_len = usize(0);
            while (items_len < header.value) {
                items_len += try self.decodeFromAlloc(in_stream, allocator);
            }

            if (items_len > header.value) {
                // Header listed length != items actual length
                return error.Overflow;
            }
        }

        pub fn decodeComplete(self: *Self) void {
            if (self._decode_builder) |*decode_builder| {
                std.debug.assert(self.value.len == 0);
                self.allocator = decode_builder.allocator;
                self.value = decode_builder.toOwnedSlice();
                self._decode_builder = null;
            }
        }
    };
}

test "Repeated" {
    var twelve = std.io.SliceInStream.init([_]u8{ 12, 0, 0, 0 });
    var hundred = std.io.SliceInStream.init([_]u8{ 100, 0, 0, 0 });

    var repeated_field = Repeated(1, Fixed32){};
    _ = try repeated_field.decodeFromAlloc(&twelve.stream, std.heap.direct_allocator);
    _ = try repeated_field.decodeFromAlloc(&hundred.stream, std.heap.direct_allocator);
    repeated_field.decodeComplete();
    testing.expectEqualSlices(u32, [_]u32{ 12, 100 }, repeated_field.value);
}
