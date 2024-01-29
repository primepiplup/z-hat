const std = @import("std");
const ip = @import("ip.zig");
const config = @import("config.zig");

const socket_t = std.os.socket_t;
const sockaddr = std.os.linux.sockaddr;
const POLL = std.os.POLL;

const MAX_CLIENTS = config.MAX_CLIENTS;
const MAX_MESSAGE_SIZE = config.MAX_MESSAGE_SIZE;
const MAX_USERNAME_SIZE = config.MAX_USERNAME_SIZE;

const stdout = std.io.getStdOut().writer();

var fds: [1 + MAX_CLIENTS]std.os.pollfd = undefined;
var connection_count: usize = 0;

var msg_buffer: [MAX_CLIENTS][MAX_USERNAME_SIZE + MAX_MESSAGE_SIZE]u8 = undefined;
var msg_count: usize = 0;

const Client = struct {
    username: [MAX_USERNAME_SIZE]u8 = undefined,
    connection: sockaddr.in = undefined,
};

var clients: [MAX_CLIENTS]Client = undefined;

pub fn main() !void {
    try serverStartListening();
    try acceptConnection();

    while(std.os.poll(fds[0..(connection_count + 1)], 3000)) |event_count| {
        if(event_count == 0) { continue; }
        try handleEvents(event_count);
    } else |_| {
        try stdout.print("Encountered an error while polling connections\n", .{});
    }

    for(0..(1 + connection_count)) |i| {
        std.os.close(fds[i].fd);
    }
}

fn handleEvents(events: usize) !void {
    var event_count = events;
    for(0..(1 + connection_count)) |i| {
        if(event_count <= 0) { break; }  // handled all events

        const poll_in_happened = fds[i].revents == POLL.IN;

        if(poll_in_happened) {
            if(i == 0) {
                try acceptConnection();
            } else {
                try readSocket(i);
            }
            event_count -= 1;
        }
    }

    if(msg_count > 0) {
        try sendMessages();
    }
}

fn serverStartListening() !void {
    const socket: socket_t = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);
    fds[0].fd = socket;
    fds[0].events = POLL.IN;

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
    try stdout.print("Listening for incoming connections..\n\n", .{});
}

fn acceptConnection() !void {
    const client: *Client = &clients[connection_count];
    var client_addr_size: u32 = 16;
    const client_socket = try std.os.accept(fds[0].fd, @ptrCast(&client.connection), &client_addr_size, 0);
    try stdout.print("Accepted client connection\n", .{});

    connection_count += 1;
    try stdout.print("Client slot {} out of capacity {}\n", .{connection_count, MAX_CLIENTS});
    fds[connection_count].fd = client_socket;
    fds[connection_count].events = POLL.IN;

    _ = try std.os.read(client_socket, &client.username);
    try stdout.print("Client username: {s}\n", .{client.username});

    var ip_buffer: [15]u8 = undefined;
    const client_ip = ip.ipStringFromAddr(&ip_buffer, client.connection.addr);
    try stdout.print("Client IP address: {s}\n\n", .{client_ip});
}

fn readSocket(client_number: usize) !void {
    const username = clients[client_number - 1].username;

    var i: usize = 0;
    while(i < username.len) {
        const c = username[i];
        if(c != 0) {
            break;
        }
        msg_buffer[msg_count][i] = c;
        i += 1;
    }

    msg_buffer[msg_count][i] = ':';
    msg_buffer[msg_count][i+1] = ' ';

    const msg = msg_buffer[msg_count][(i+2)..];

    const code = try std.os.recv(fds[client_number].fd, msg, 0);
    if(code == 0) { //connection was closed by this client
        try stdout.print("Lost connection to client {}, username: {s}\n", .{client_number, username});
        return; // have to fix the array of client structs because there is now a gap
    }

    try stdout.print("{s}: {s}", .{username, msg});
    msg_count += 1;
}

fn sendMessages() !void {
    for(0..msg_count) |msg_idx| {
        for(0..connection_count) |cn_idx| {
            _ = try std.os.send(fds[cn_idx + 1].fd, &msg_buffer[msg_idx], 0);
        }
        @memset(&msg_buffer[msg_idx], 0);
    }
}

