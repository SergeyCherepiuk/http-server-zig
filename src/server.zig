const std = @import("std");
const io = std.io;
const os = std.os;
const net = std.net;
const mem = std.mem;

pub const io_mode = io.Mode.blocking;

const UnbufferedWriter = @import("common/writer.zig").UnbufferedWriter;

pub const SocketOptions = struct {
    domain: u32,
    type: u32,
    protocol: u32,
    accept_flags: u32,
};

pub const TCPServer = struct {
    allocator: mem.Allocator,
    address: net.Address,
    socket_options: SocketOptions,

    pub fn init(allocator: mem.Allocator, host: []const u8, port: u16) !TCPServer {
        const address = try net.Address.parseIp(host, port);
        const nonblock = if (io_mode == io.Mode.evented) os.SOCK.NONBLOCK else 0;
        return TCPServer{
            .allocator = allocator,
            .address = address,
            .socket_options = .{
                .domain = address.any.family,
                .type = os.SOCK.STREAM | nonblock | os.SOCK.CLOEXEC,
                .protocol = os.IPPROTO.TCP,
                .accept_flags = os.SOCK.CLOEXEC,
            },
        };
    }

    pub const StartOptions = struct { backlog: u31 = 10 };

    pub fn start(self: *TCPServer, options: StartOptions) !void {
        var socket = try os.socket(
            self.socket_options.domain,
            self.socket_options.type,
            self.socket_options.protocol,
        );
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
            const connection = try self.accept(socket);

            const message = try self.receive(connection);
            _ = try self.send(connection, message);

            os.closeSocket(connection);
        }
    }

    fn accept(self: TCPServer, socket: os.socket_t) !os.socket_t {
        const peer_socket_address = try self.allocator.create(net.Address);
        peer_socket_address.any.family = os.AF.INET; // TODO: Review usage INET here
        const peer_socket_length = self.address.getOsSockLen();

        const connection = try os.accept(
            socket,
            @constCast(&peer_socket_address.any),
            @constCast(&peer_socket_length),
            self.socket_options.accept_flags,
        );

        var buf = UnbufferedWriter.init(self.allocator);
        try peer_socket_address.format("", .{}, buf.writer());
        std.log.info("Connection established with {s}", .{buf.buffer()});

        return connection;
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

    fn send(self: TCPServer, connection: os.socket_t, message: []const u8) !usize {
        const socket_address = @constCast(&self.address.any);
        const socket_length = self.address.getOsSockLen();

        const bytes_read = try os.sendto(connection, message, 0, socket_address, socket_length);

        std.log.info("Sent: \"{s}\" ({d} bytes)", .{ message, bytes_read });

        return bytes_read;
    }
};
