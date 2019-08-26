const std = @import("std");

pub const AutoAllocOutStream = struct {
    list: std.ArrayList(u8),

    pub fn init(allocator: *std.mem.Allocator) AutoAllocOutStream {
        return AutoAllocOutStream{
            .list = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *AutoAllocOutStream) void {
        return self.deinit();
    }

    pub fn write(self: *AutoAllocOutStream, bytes: []const u8) !void {
        self.list.appendSlice(bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.NoSpaceLeft,
        };
    }

    pub fn toSlice(self: *AutoAllocOutStream) []u8 {
        return self.list.toSlice();
    }

    pub fn toOwnedSlice(self: *AutoAllocOutStream) []u8 {
        return self.list.toOwnedSlice();
    }
};
