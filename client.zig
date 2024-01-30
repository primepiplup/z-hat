const std = @import("std");
const ip = @import("ip.zig");
const config = @import("config.zig");

const MAX_USERNAME_SIZE = config.MAX_USERNAME_SIZE;
const MAX_MESSAGE_SIZE = config.MAX_MESSAGE_SIZE;
const USERNAME_MSG_OFFSET = config.USERNAME_MSG_OFFSET;

var fds: [2]std.os.pollfd = undefined;

const stdin_file = std.io.getStdIn();
const stdin = stdin_file.reader();
const stdout = std.io.getStdOut().writer();

var msg_buffer: [MAX_USERNAME_SIZE + USERNAME_MSG_OFFSET + MAX_MESSAGE_SIZE]u8 = undefined;

pub fn main() !void {
    const socket = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    defer std.os.close(socket);

    const ip_addr = try ip.ipAddr(config.SERVER_IP);

    var pad: [8]u8 = undefined;
    @memset(&pad, 0);

    const sock_addr = std.os.linux.sockaddr.in {
        .family = std.os.linux.AF.INET,
        .port = ip.networkPort(config.SERVER_PORT),
        .addr = ip_addr,
        .zero = pad,
    };

    var message: [1000]u8 = undefined;
    var username_buffer: [MAX_USERNAME_SIZE]u8 = undefined;
    @memset(&username_buffer, 0);
    @memset(&message, 0);

    try stdout.print("Provide a username, max 25 characters.\n", .{});
    const username_len = getInput(username_buffer[0..]) catch return;

    _ = try std.os.connect(socket, @ptrCast(&sock_addr), 16);
    _ = try std.os.send(socket, username_buffer[0..username_len], 0);

    fds[0].fd = socket;
    fds[0].events = std.os.POLL.IN;
    fds[1].fd = stdin_file.handle;
    fds[1].events = std.os.POLL.IN | std.os.POLL.HUP;

    try stdout.print("Ready to send messages.\n", .{});
    while(!std.mem.eql(u8, &message, "/quit")) {
        const event_count = try std.os.poll(&fds, 3000);
        if(event_count <= 0) { continue; }
        if(fds[1].revents == std.os.POLL.IN) {
            const message_len = getInput(&message) catch return;
            _ = try std.os.send(socket, message[0..(message_len+1)], 0);
            clearMessage(&message, message_len);
        } else if (fds[0].revents == std.os.POLL.IN) {
            _ = try std.os.recv(fds[0].fd, &msg_buffer, 0);
            try stdout.print("{s}", .{msg_buffer});
            @memset(&msg_buffer, 0);
        }
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

