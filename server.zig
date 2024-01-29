const std = @import("std");
const ip = @import("ip.zig");

pub fn main() !void {
    const socket: std.os.socket_t = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    const ip_addr = try ip.ipAddr("127.0.0.1");

    var pad: [8]u8 = undefined;
    @memset(&pad, 0);

    const sock_addr = std.os.linux.sockaddr.in {
        .family = std.os.linux.AF.INET,
        .port = ip.networkPort(6789),
        .addr = ip_addr,
        .zero = pad,
    };
    try std.os.bind(socket, @ptrCast(&sock_addr), 16);
    try std.os.listen(socket, 10);

    var buffer: [1000]u8 = undefined;

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Bound socket.\n", .{});

    var client_addr: std.os.linux.sockaddr = undefined;
    var client_addr_size: u32 = 16;
    const client = try std.os.accept(socket, &client_addr, &client_addr_size, 0);

    try stdout.print("Accepted client connection.\n", .{});

    while(std.os.read(client, &buffer)) |len| {
        if(len <= 0) {
            try stdout.print("Client closed connection.\n", .{});
            break;
        }
        try stdout.print("{s}", .{buffer});
    } else |_| {
        try stdout.print("Encountered read error\n", .{});
    }


    std.os.close(socket);
}

const SockAddrIn = struct {
    Addr: InAddr,
};

const InAddr = struct {
    ip_addr: u32,
};


