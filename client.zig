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
    try os.connect(sock, &sock_addr, sock_len);

    const buf = "test message";
    const n = try os.send(sock, buf, 0);
    std.debug.print("Sent message: \"{s}\" ({d} bytes)\n", .{ buf, n });
}
