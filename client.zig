const std = @import("std");
const ip = @import("ip.zig");
const config = @import("config.zig");
const c = @cImport({ @cInclude("curses.h"); });

const MAX_USERNAME_SIZE   = config.MAX_USERNAME_SIZE;
const MAX_MESSAGE_SIZE    = config.MAX_MESSAGE_SIZE;
const USERNAME_MSG_OFFSET = config.USERNAME_MSG_OFFSET;

var fds: [2]std.os.pollfd = undefined;

const stdin_file = std.io.getStdIn();
const stdin      = stdin_file.reader();
const stdout     = std.io.getStdOut().writer();

var receive_buffer:  [MAX_USERNAME_SIZE + USERNAME_MSG_OFFSET + MAX_MESSAGE_SIZE:0]u8 = undefined;
var message_buffer:  [MAX_MESSAGE_SIZE:0]u8 = undefined;
var username_buffer: [MAX_USERNAME_SIZE]u8  = undefined;

var stdwin:     ?*c.WINDOW = null;
var msgwin:     ?*c.WINDOW = null;
var inputwin:   ?*c.WINDOW = null;
var height: c_int = 0;
var width:  c_int = 0;

const EXIT: [*:0]const u8 = "/quit";
const HELP: [*:0]const u8 = "/help";

pub fn main() !void {
    const socket = try std.os.socket(std.os.AF.INET, std.os.SOCK.STREAM, 0);

    fds[0].fd     = socket;
    fds[0].events = std.os.POLL.IN | std.os.POLL.HUP;
    fds[1].fd     = stdin_file.handle;
    fds[1].events = std.os.POLL.IN;

    defer gracefulShutdown("User quit program.", 0);

    @memset(&username_buffer, 0);
    @memset(&message_buffer, 0);

    try stdout.print("Provide a username, max 25 characters.\n", .{});
    const username_len = getInput(username_buffer[0..]) catch return;

    initScreen();

    const sock_addr = try buildSockAddr();
    _ = std.os.connect(socket, @ptrCast(&sock_addr), 16) catch { gracefulShutdown("No server could be found", 4); };
    _ = std.os.send(socket, username_buffer[0..username_len], 0) catch { gracefulShutdown("Was unable to send username to server, quitting.", 2); };

    _ = c.wprintw(msgwin, "Connected to server\n");
    _ = c.wrefresh(msgwin);

    while(true) {
        const event_count = try std.os.poll(&fds, 3000);
        if(event_count <= 0) { continue; }

        if (fds[0].revents == std.os.POLL.IN) {
            try readReceived();
            try displayReceived();
        } else if (fds[0].revents & std.os.POLL.HUP == std.os.POLL.HUP) {
            // server disconnect
            gracefulShutdown("Lost connection to the server - it probably was shut down", 0);
        } else if (fds[1].revents == std.os.POLL.IN) {
            _ = c.wgetnstr(inputwin, &message_buffer, MAX_MESSAGE_SIZE - 1);
            const msg: [*:0]const u8 = &message_buffer;
            if(std.mem.orderZ(u8, msg, EXIT).compare(.eq)) { break; }
            if(std.mem.orderZ(u8, msg, HELP).compare(.eq)) { try provideHelp(); }
            _ = try std.os.send(socket, std.mem.span(msg), 0);
            clearMessage(&message_buffer);
        }
    }
}

fn gracefulShutdown(reason: []const u8, statuscode: u8) void {
    if(stdwin != null) {
        _ = c.endwin();
    }

    std.debug.print("{s}\n", .{reason});

    std.os.close(fds[0].fd);
    std.os.close(fds[1].fd);
    
    std.process.exit(statuscode);
}

fn initScreen() void {
    stdwin = c.initscr();

    height = c.LINES;
    width  = c.COLS;

    if(height < 5 or width < 10) {
        gracefulShutdown("Terminal too small, quitting.", 3);
    }
    
    msgwin = c.newwin(height - 3, width - 2, 1, 1);
    inputwin = c.newwin(1, width - 2, height - 1, 1);

    _ = c.scrollok(msgwin,   true);
    _ = c.scrollok(inputwin, true);

    _ = c.refresh();
}

fn buildSockAddr() !std.os.sockaddr.in {
    const ip_addr = try ip.ipAddr(config.SERVER_IP);

    var pad: [8]u8 = undefined;
    @memset(&pad, 0);

    return std.os.linux.sockaddr.in {
        .family = std.os.linux.AF.INET,
        .port   = ip.networkPort(config.SERVER_PORT),
        .addr   = ip_addr,
        .zero   = pad,
    };
}

fn readReceived() !void {
    const msg_len = try std.os.recv(fds[0].fd, &receive_buffer, 0);
    if (msg_len <= 0) {
        gracefulShutdown("Lost connection to the server - it probably was shut down", 0);
    }
}

fn displayReceived() !void {
    const received: [*:0]const u8 = &receive_buffer;
    _ = c.wprintw(msgwin, received);
    _ = c.wprintw(msgwin, "\n");
    @memset(&receive_buffer, 0);
    _ = c.wrefresh(msgwin);
    _ = c.wclear(inputwin);
    _ = c.wrefresh(inputwin);
}

fn clearMessage(buffer: []u8) void {
    @memset(buffer, 0);
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

fn provideHelp() !void {
    _ = c.wprintw(msgwin, "\n");
    _ = c.wprintw(msgwin, "Use /quit to quit\n");
    _ = c.wprintw(msgwin, "Use /online to view the users that are currently online\n");
    _ = c.wprintw(msgwin, "Use /help to display this message\n");
    _ = c.wprintw(msgwin, "\n");
    _ = c.wrefresh(msgwin);
    _ = c.wclear(inputwin);
    _ = c.wrefresh(inputwin);
    clearMessage(&message_buffer);
}
