const std = @import("std");
const os = std.os;
const net = std.net;

pub fn main() !void {
    const sock_domain = os.system.PF.INET;
    const sock_type = os.system.SOCK.STREAM;
    const sock_protocol = os.system.IPPROTO.TCP;
    var sock = try os.socket(sock_domain, sock_type, sock_protocol);

    const localhost = try net.Address.parseIp4("127.0.0.1", 6969);
    const sock_addr = localhost.any;
    const sock_len = localhost.getOsSockLen();
    try os.bind(sock, &sock_addr, sock_len);

    const backlog = 10;
    try os.listen(sock, backlog);

    const sock_flags = 0;
    var buf: [100]u8 = undefined;
    while (true) {
        const conn = try os.accept(
            sock,
            @constCast(&sock_addr),
            @constCast(&sock_len),
            sock_flags,
        );

        const n = try os.recv(conn, &buf, 0);
        std.debug.print("Received message: \"{s}\" ({d} bytes)\n", .{ buf[0..n], n });

        os.close(conn);
    }
}
