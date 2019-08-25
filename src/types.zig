const std = @import("std");
const coder = @import("coder.zig");
const testing = std.testing;

const ParseError = coder.ParseError;

pub const BufferedWriter = struct {
    list: std.ArrayList(u8),

    pub fn init(allocator: *std.mem.Allocator) BufferedWriter {
        return BufferedWriter{
            .list = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *BufferedWriter) void {
        return self.deinit();
    }

    pub fn write(self: *BufferedWriter, bytes: []const u8) std.os.WriteError!void {
        self.list.appendSlice(bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.NoSpaceLeft,
        };
    }

    pub fn toSlice(self: *BufferedWriter) []u8 {
        return self.list.toSlice();
    }

    pub fn toOwnedSlice(self: *BufferedWriter) []u8 {
        return self.list.toOwnedSlice();
    }
};

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

    pub fn encodeInto(self: FieldMeta, comptime Writer: type, writer: *Writer) !void {
        const uint = (@intCast(u64, self.number) << 3) + @enumToInt(self.wire_type);
        try coder.Uint64Coder.encodeInto(Writer, writer, uint);
    }

    pub fn decode(buffer: []const u8, len: *usize) ParseError!FieldMeta {
        const raw = try coder.Uint64Coder.decode(buffer, len);
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

        data: TargetPrimitive = 0,

        pub const field_meta = info;

        pub fn encodeSize(self: Self) usize {
            return Coder.encodeSize(@bitCast(Coder.primitive, self.data));
        }

        pub fn encodeInto(self: Self, comptime Writer: type, writer: *Writer) !void {
            try Coder.encodeInto(Writer, writer, @bitCast(Coder.primitive, self.data));
        }

        pub fn decodeFrom(self: *Self, buffer: []const u8) ParseError!usize {
            var len: usize = undefined;
            const raw = try Coder.decode(buffer, &len);
            self.data = @bitCast(TargetPrimitive, raw);
            return len;
        }
    };
}

fn FromVarintCast(comptime TargetPrimitive: type, comptime Coder: type, comptime info: FieldMeta) type {
    return struct {
        const Self = @This();

        data: TargetPrimitive = 0,

        pub const field_meta = info;

        pub fn encodeSize(self: Self) usize {
            return Coder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, comptime Writer: type, writer: *Writer) !void {
            try Coder.encodeInto(Writer, writer, self.data);
        }

        pub fn decodeFrom(self: *Self, buffer: []const u8) ParseError!usize {
            var len: usize = undefined;
            const raw = try Coder.decode(buffer, &len);
            self.data = @intCast(TargetPrimitive, raw);
            return len;
        }
    };
}

var rng = std.rand.DefaultPrng.init(0);
fn testEncodeDecode(comptime T: type, base: T) !void {
    var writer = BufferedWriter.init(std.heap.direct_allocator);

    try base.encodeInto(BufferedWriter, &writer);
    testing.expectEqual(base.encodeSize(), writer.toSlice().len);

    var decoded: T = undefined;
    const decoded_len = try decoded.decodeFrom(writer.toSlice());
    testing.expectEqual(base.data, decoded.data);
    testing.expectEqual(base.encodeSize(), decoded_len);
}

fn testEncodeDecodeSlices(comptime T: type, base: T) !void {
    var writer = BufferedWriter.init(std.heap.direct_allocator);

    try base.encodeInto(BufferedWriter, &writer);
    testing.expectEqual(base.encodeSize(), writer.toSlice().len);

    var decoded: T = undefined;
    const decoded_len = try decoded.decodeFromAlloc(writer.toSlice(), std.heap.direct_allocator);
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

        data: []u8 = [_]u8{},
        allocator: ?*std.mem.Allocator = null,

        pub const field_meta = FieldMeta{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn deinit(self: *Self) void {
            if (self.allocator) |alloc| {
                alloc.free(self.data);
                self.* = Self{};
            }
        }

        pub fn encodeSize(self: Self) usize {
            return coder.BytesCoder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, comptime Writer: type, writer: *Writer) !void {
            try coder.BytesCoder.encodeInto(Writer, writer, self.data);
        }

        pub fn decodeFromAlloc(self: *Self, buffer: []const u8, allocator: *std.mem.Allocator) ParseError!usize {
            var len: usize = undefined;
            self.data = try coder.BytesCoder.decode(buffer, &len, allocator);
            self.allocator = allocator;
            return len;
        }
    };
}

pub fn String(comptime number: u63) type {
    return struct {
        const Self = @This();

        data: []const u8 = "",
        allocator: ?*std.mem.Allocator = null,

        pub const field_meta = FieldMeta{
            .wire_type = .LengthDelimited,
            .number = number,
        };

        pub fn deinit(self: *Self) void {
            if (self.allocator) |alloc| {
                alloc.free(self.data);
                self.* = Self{};
            }
        }

        pub fn encodeSize(self: Self) usize {
            return coder.BytesCoder.encodeSize(self.data);
        }

        pub fn encodeInto(self: Self, comptime Writer: type, writer: *Writer) !void {
            try coder.BytesCoder.encodeInto(Writer, writer, self.data);
        }

        pub fn decodeFromAlloc(self: *Self, buffer: []const u8, allocator: *std.mem.Allocator) ParseError!usize {
            // TODO: validate unicode
            var len: usize = undefined;
            self.data = try coder.BytesCoder.decode(buffer, &len, allocator);
            self.allocator = allocator;
            return len;
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

        data: bool = false,

        pub const field_meta = FieldMeta{
            .wire_type = .Varint,
            .number = number,
        };

        pub fn encodeSize(self: Self) usize {
            return 1;
        }

        pub fn encodeInto(self: Self, comptime Writer: type, writer: *Writer) !void {
            const value = if (self.data) [_]u8{1} else [_]u8{0};
            try writer.write(value[0..]);
        }

        pub fn decodeFrom(self: *Self, bytes: []const u8) ParseError!usize {
            var len: usize = undefined;
            const raw = try coder.Uint64Coder.decode(bytes, &len);
            // TODO: verify that bools *must* be 0 or 1
            if (raw > 1) {
                return error.Overflow;
            }
            self.data = raw != 0;
            return len;
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
    std.debug.assert(@hasDecl(T, "decodeFrom"));

    const DataType = std.meta.fieldInfo(T, "data").field_type;

    return struct {
        const Self = @This();
        const List = std.ArrayList(DataType);

        data: []DataType = [_]DataType{},
        allocator: ?*std.mem.Allocator = null,
        _decode_builder: ?List = null,

        pub fn deinit(self: *Self) void {
            if (self._decode_builder) |*decode_builder| {
                std.debug.assert(self.data.len == 0);
                decode_builder.deinit();
                self.* = Self{};
            } else if (self.allocator) |alloc| {
                alloc.free(self.data);
                self.* = Self{};
            }
        }

        pub fn encodeSize(self: Self) usize {
            var sum = usize(0);
            for (self.data) |item| {
                const wrapper = DataType{ .data = item };
                sum += wrapper.encodeSize();
            }
            return sum;
        }

        pub fn encodeInto(self: Self, comptime Writer: type, writer: *Writer) !void {
            for (self.data) |item| {
                const wrapper = DataType{ .data = item };
                wrapper.encodeInto(Writer, writer);
            }
        }

        pub fn decodeFromAlloc(self: *Self, raw: []const u8, allocator: *std.mem.Allocator) ParseError!usize {
            if (self._decode_builder == null) {
                self.deinit();
                self._decode_builder = List.init(allocator);
            }
            var base: T = undefined;
            const len = try base.decodeFrom(raw);
            try self._decode_builder.?.append(base.data);
            return len;
        }

        pub fn decodePacked(self: *Self, raw: []const u8, allocator: *std.mem.Allocator) ParseError!usize {
            var header_len: usize = undefined;
            const header = try Uint64.decode(raw, &header_len);

            var items_len = usize(0);
            while (items_len < header.data) {
                items_len += try self.decodeFromAlloc(raw[header_len + items_len ..], &len, allocator);
            }

            if (items_len > header.data) {
                // Header listed length != items actual length
                return error.Overflow;
            }

            len.* = header_len + items_len;
        }

        pub fn decodeComplete(self: *Self) void {
            if (self._decode_builder) |*decode_builder| {
                std.debug.assert(self.data.len == 0);
                self.allocator = decode_builder.allocator;
                self.data = decode_builder.toOwnedSlice();
                self._decode_builder = null;
            }
        }
    };
}

test "Repeated" {
    const twelve = [_]u8{ 12, 0, 0, 0 };
    const hundred = [_]u8{ 100, 0, 0, 0 };

    var repeated_field = Repeated(1, Fixed32){};
    _ = try repeated_field.decodeFromAlloc(twelve[0..], std.heap.direct_allocator);
    _ = try repeated_field.decodeFromAlloc(hundred[0..], std.heap.direct_allocator);
    repeated_field.decodeComplete();
    testing.expectEqualSlices(u32, [_]u32{ 12, 100 }, repeated_field.data);
}
