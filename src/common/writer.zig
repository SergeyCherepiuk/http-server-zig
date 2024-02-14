const std = @import("std");
const mem = std.mem;
const io = std.io;

pub const UnbufferedWriter = struct {
    buf: std.ArrayList(u8),

    pub fn init(allocator: mem.Allocator) UnbufferedWriter {
        return UnbufferedWriter{ .buf = std.ArrayList(u8).init(allocator) };
    }

    pub fn buffer(self: UnbufferedWriter) []const u8 {
        return self.buf.items;
    }

    pub fn writer(self: *UnbufferedWriter) Writer {
        return .{ .context = self };
    }

    const Writer = io.Writer(*UnbufferedWriter, WriteError, write);

    pub const WriteError = mem.Allocator.Error;

    fn write(self: *UnbufferedWriter, data: []const u8) WriteError!usize {
        try self.buf.appendSlice(data);
        return data.len;
    }
};
