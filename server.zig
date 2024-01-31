const std = @import("std");
const ip = @import("ip.zig");
const config = @import("config.zig");

const socket_t = std.os.socket_t;
const sockaddr = std.os.linux.sockaddr;
const POLL     = std.os.POLL;

const MAX_CLIENTS         = config.MAX_CLIENTS;
const MAX_MESSAGE_SIZE    = config.MAX_MESSAGE_SIZE;
const MAX_USERNAME_SIZE   = config.MAX_USERNAME_SIZE;
const USERNAME_MSG_OFFSET = config.USERNAME_MSG_OFFSET;

const stdout = std.io.getStdOut().writer();

var fds: [1 + MAX_CLIENTS]std.os.pollfd = undefined;
var connection_count: usize = 0;

var msg_len_buffer: [MAX_CLIENTS]usize = undefined;
var msg_buffer: [MAX_CLIENTS][MAX_USERNAME_SIZE + USERNAME_MSG_OFFSET + MAX_MESSAGE_SIZE:0]u8 = undefined;
var msg_count: usize = 0;

var discard: [16]u8 = undefined;
var broadcast_buffer: [200]u8 = undefined;

const Client = struct {
    username:   [MAX_USERNAME_SIZE:0]u8 = undefined,
    connection: sockaddr.in           = undefined,
};

var clients: [MAX_CLIENTS]Client = undefined;

pub fn main() !void {
    try serverStartListening();
    try acceptConnection();
    defer cleanSockets(0);

    try std.os.sigaction(std.os.SIG.INT, &std.os.Sigaction{
        .handler = .{ .handler = cleanSockets },
        .mask = std.os.empty_sigset,
        .flags = 0 }
        , null);

    while(std.os.poll(fds[0..(connection_count + 1)], 3000)) |event_count| {
        if(event_count == 0) { continue; }
        try handleEvents(event_count);
    } else |_| {
        try stdout.print("Encountered an error while polling connections\n", .{});
    }
}

fn cleanSockets(_: c_int) callconv(.C) void {
    std.debug.print("Shutting down, clearing sockets.\n", .{});
    for(0..(1 + connection_count)) |i| {
        std.os.close(fds[i].fd);
    }
    std.process.exit(1);
}

fn handleEvents(events: usize) !void {
    var event_count = events;
    for(0..(1 + connection_count)) |i| {
        if(event_count <= 0) { break; }  // handled all events

        const poll_in_happened = fds[i].revents == POLL.IN;
        const poll_hung_up = fds[i].revents & POLL.HUP == POLL.HUP;

        if(poll_in_happened) {
            if(i == 0) {
                try acceptConnection();
            } else {
                try readSocket(i);
            }
            event_count -= 1;
        } else if(poll_hung_up) {
            try cleanConnection(i);
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

    const ip_addr = try ip.ipAddr(config.SERVER_IP);

    var pad: [8]u8 = undefined;
    @memset(&pad, 0);

    const sock_addr = sockaddr.in {
        .family = std.os.linux.AF.INET,
        .port = ip.networkPort(config.SERVER_PORT),
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
    fds[connection_count].events = POLL.IN | POLL.HUP;

    _ = try std.os.read(client_socket, &client.username);
    try stdout.print("Client username: {s}\n", .{client.username});

    var ip_buffer: [15]u8 = undefined;
    const client_ip = ip.ipStringFromAddr(&ip_buffer, client.connection.addr);
    try stdout.print("Client IP address: {s}\n\n", .{client_ip});

    try broadcast("server message --- user '{s}' connected", .{@as([*:0]const u8, &client.username)});
}

fn readSocket(client_number: usize) !void {
    const username = clients[client_number - 1].username;

    var i: usize = 0;
    while(i < username.len) {
        const c = username[i];
        if(c == 0) {
            break;
        }
        msg_buffer[msg_count][i] = c;
        i += 1;
    }

    msg_buffer[msg_count][i] = ':';
    msg_buffer[msg_count][i+1] = ' ';

    const msg = msg_buffer[msg_count][(i+2)..];

    const msg_len = try std.os.recv(fds[client_number].fd, msg, 0);
    msg_len_buffer[msg_count] = msg_len;
    if(msg_len == 0) {
        try stdout.print("Tried to read message, but lost connection\n", .{});
        try cleanConnection(client_number);
        return; 
    }

    try stdout.print("{s}\n", .{msg_buffer[msg_count]});
    msg_count += 1;
}

fn sendMessages() !void {
    for(0..msg_count) |msg_idx| {
        for(0..connection_count) |cn_idx| {
            const msg_slice = msg_buffer[msg_idx][0..(MAX_USERNAME_SIZE + USERNAME_MSG_OFFSET + msg_len_buffer[msg_idx] + 1)];
            _ = try std.os.send(fds[cn_idx + 1].fd, msg_slice, 0);
        }
        @memset(&msg_buffer[msg_idx], 0);
    }
    msg_count = 0;
}

fn cleanConnection(cn_idx: usize) !void {
    _ = try std.os.read(fds[cn_idx].fd, &discard);
    fds[cn_idx] = fds[connection_count];
    connection_count -= 1;

    try stdout.print("Cleaned lost connection to client {}, username: {s}\n", .{cn_idx, clients[cn_idx - 1].username});

    const c_username: [*:0]const u8 = &clients[cn_idx - 1].username;
    try broadcast("server message --- user '{s}' disconnected", .{c_username});
    @memset(&clients[cn_idx - 1].username, 0);

    clients[cn_idx - 1] = clients[connection_count];
    @memset(&clients[connection_count].username, 0);
}

fn broadcast(comptime fmt_str: []const u8, args: anytype) !void {   // send a message to all clients, irrespective of the message buffer. Used for server communication to its clients
    const brdcst = try std.fmt.bufPrint(&broadcast_buffer, fmt_str, args);
    for(0..connection_count) |cn_idx| {
        _ = try std.os.send(fds[cn_idx + 1].fd, brdcst, 0);
    }
} 

