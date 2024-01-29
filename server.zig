const std = @import("std");
const ip = @import("ip.zig");

const socket_t = std.os.socket_t;
const sockaddr = std.os.linux.sockaddr;

const stdout = std.io.getStdOut().writer();
const MAX_CLIENTS = 10;
const MAX_MESSAGE_SIZE = 1000;

pub fn main() !void {
    const socket = try serverStartListening();
    defer std.os.close(socket);

    var buffer: [MAX_MESSAGE_SIZE]u8 = undefined;

    const client = try acceptConnection(socket);

    while(std.os.read(client, &buffer)) |len| {
        if(len <= 0) {
            try stdout.print("Client closed connection.\n", .{});
            break;
        }
        try stdout.print("{s}", .{buffer});
    } else |_| {
        try stdout.print("Encountered read error\n", .{});
    }
}

fn serverStartListening() !socket_t {
    const socket: socket_t = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    const ip_addr = try ip.ipAddr("127.0.0.1");

    var pad: [8]u8 = undefined;
    @memset(&pad, 0);

    const sock_addr = sockaddr.in {
        .family = std.os.linux.AF.INET,
        .port = ip.networkPort(6789),
        .addr = ip_addr,
        .zero = pad,
    };
    try std.os.bind(socket, @ptrCast(&sock_addr), 16);
    try stdout.print("Bound socket.\n", .{});

    try std.os.listen(socket, 10);
    try stdout.print("Listening for incoming connections..\n", .{});

    return socket;
}

fn acceptConnection(socket: socket_t) !socket_t {
    var client_addr: sockaddr = undefined;
    var client_addr_size: u32 = 16;
    const client = try std.os.accept(socket, &client_addr, &client_addr_size, 0);

    try stdout.print("Accepted client connection.\n", .{});
    return client;
}

