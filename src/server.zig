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
        defer buf.deinit();
        try self.address.format("", .{}, buf.writer());
        std.log.info("Server is listening on port {s}", .{buf.buffer()});

        while (true) {
            const peer = try self.accept(socket);

            const message = try self.receive(peer);
            if (message.ok) {
                _ = try self.send(peer, message.message);
            }

            os.closeSocket(peer.socket);
        }
    }

    const Peer = struct {
        socket: os.socket_t,
        socket_address: os.sockaddr,
        socket_length: os.socklen_t,
    };

    fn accept(self: TCPServer, socket: os.socket_t) !Peer {
        const peer_socket_address = try self.allocator.create(net.Address);
        peer_socket_address.any.family = self.address.any.family;
        const peer_socket_length = self.address.getOsSockLen();

        const accept_flags = 0;
        const peer_socket = try os.accept(
            socket,
            @constCast(&peer_socket_address.any),
            @constCast(&peer_socket_length),
            accept_flags,
        );

        var buf = UnbufferedWriter.init(self.allocator);
        defer buf.deinit();
        try peer_socket_address.format("", .{}, buf.writer());
        std.log.info("Connection established with {s}", .{buf.buffer()});

        return Peer{
            .socket = peer_socket,
            .socket_address = peer_socket_address.any,
            .socket_length = peer_socket_length,
        };
    }

    const Message = struct { message: []const u8, ok: bool };

    fn receive(self: TCPServer, peer: Peer) !Message {
        var message = std.ArrayList(u8).init(self.allocator);

        var buf: [256]u8 = undefined;
        while (true) {
            var fd = os.pollfd{ .fd = peer.socket, .events = os.POLL.IN, .revents = 0 };
            const available = try os.poll(@constCast(&[_]os.pollfd{fd}), 0);
            if (available <= 0) break;

            const bytes_read = try os.recv(peer.socket, &buf, 0);
            if (bytes_read == 0) {
                message.deinit();
                return Message{ .message = "", .ok = false };
            }

            try message.appendSlice(buf[0..bytes_read]);
        }

        std.log.info("Received: \"{s}\" ({d} bytes)", .{ message.items, message.items.len });

        return Message{ .message = message.items, .ok = true };
    }

    fn send(_: TCPServer, peer: Peer, message: []const u8) !usize {
        const send_flags = 0;
        const bytes_read = try os.send(peer.socket, message, send_flags);

        std.log.info("Sent: \"{s}\" ({d} bytes)", .{ message, bytes_read });

        return bytes_read;
    }
};
