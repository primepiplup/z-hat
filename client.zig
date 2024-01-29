const std = @import("std");
const ip = @import("ip.zig");

const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    const socket = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    defer std.os.close(socket);

    const ip_addr = try ip.ipAddr("127.0.0.1");

    var pad: [8]u8 = undefined;
    @memset(&pad, 0);

    const sock_addr = std.os.linux.sockaddr.in {
        .family = std.os.linux.AF.INET,
        .port = ip.networkPort(6789),
        .addr = ip_addr,
        .zero = pad,
    };
    _ = try std.os.connect(socket, @ptrCast(&sock_addr), 16);

    const u_len = 25;

    var buffer: [1000]u8 = undefined;
    const username: []u8 = buffer[0..u_len];
    @memset(username, 0);
    const message: []u8 = buffer[(u_len+1)..];
    @memset(message, 0);

    buffer[u_len] = ' ';

    try stdout.print("Provide a username, max 25 characters.\n", .{});
    const user_len = getInput(username) catch return;
    username[user_len] = ':';

    try stdout.print("Ready to send messages.\n", .{});
    while(!std.mem.eql(u8, message, "/quit")) {
        const message_len = getInput(message) catch return;

        _ = try std.os.send(socket, &buffer, 0);
        clearMessage(message, message_len);
    }
}

fn clearMessage(buffer: []u8, length: usize) void {
    for(0..(length+1)) |i| {
        buffer[i] = 0;
    }
}

fn getInput(buffer: []u8) !usize {
    const res = stdin.readUntilDelimiter(buffer, '\n') catch |err| switch (err) {
        error.StreamTooLong => {
            try stdout.print("Input was too large.\n", .{});
            try stdin.skipUntilDelimiterOrEof('\n');
            return error.StreamTooLong;
        },
        else => |e| {
            try stdout.print("Other error occurred.\n", .{});
            return e;
        },
    };
    return res.len;
}

