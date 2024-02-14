const std = @import("std");
const os = std.os;
const net = std.net;
const mem = std.mem;

const UnbufferedWriter = @import("common/writer.zig").UnbufferedWriter;

pub const TCPServer = struct {
    allocator: mem.Allocator,
    address: net.Address,

    const socket_domain = os.system.AF.INET;
    const socket_type = os.system.SOCK.STREAM;
    const socket_protocol = os.system.IPPROTO.TCP;
    const socket_accept_flags = 0;

    pub fn init(allocator: mem.Allocator, host: []const u8, port: u16) !TCPServer {
        return TCPServer{
            .allocator = allocator,
            .address = try net.Address.parseIp(host, port),
        };
    }

    pub const StartOptions = struct { backlog: u31 = 10 };

    pub fn start(self: *TCPServer, options: StartOptions) !void {
        var socket = try os.socket(socket_domain, socket_type, socket_protocol);
        defer os.closeSocket(socket);

        const socket_address = @constCast(&self.address.any);
        const socket_length = @constCast(&self.address.getOsSockLen());

        try os.bind(socket, socket_address, socket_length.*);
        try os.getsockname(socket, socket_address, socket_length);
        try os.listen(socket, options.backlog);

        var buf = UnbufferedWriter.init(self.allocator);
        try self.address.format("", .{}, buf.writer());
        std.log.info("Server is listening on port {s}", .{buf.buffer()});

        while (true) {
            const connection = try os.accept(socket, socket_address, socket_length, socket_accept_flags);

            const message = try self.receive(connection);
            _ = try self.send(connection, message);

            os.closeSocket(connection);
        }
    }

    fn receive(self: TCPServer, connection: os.socket_t) ![]const u8 {
        var message = std.ArrayList(u8).init(self.allocator);

        var buf: [256]u8 = undefined;
        while (true) {
            var file_descriptors = [_]os.pollfd{.{
                .fd = connection,
                .events = os.POLL.IN,
                .revents = 0,
            }};
            const available = try os.poll(&file_descriptors, 0);
            if (available <= 0) break;

            const bytes_read = try os.recv(connection, &buf, 0);
            try message.appendSlice(buf[0..bytes_read]);
        }

        std.log.info("Received: \"{s}\" ({d} bytes)", .{ message.items, message.items.len });

        return message.items;
    }

    fn send(_: TCPServer, connection: os.socket_t, message: []const u8) !usize {
        const bytes_read = try os.send(connection, message, 0);

        std.log.info("Sent: \"{s}\" ({d} bytes)", .{ message, bytes_read });

        return bytes_read;
    }
};

pub fn main() !void {
    var server = try TCPServer.init(std.heap.page_allocator, "127.0.0.1", 0);
    try server.start(.{});
}
