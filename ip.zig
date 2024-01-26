const std = @import("std");

pub const IpError = error {
    IpIncorrectError,
};

pub fn ipAddr(addr_str: []const u8) IpError!u32 {
    var tokens = std.mem.tokenizeAny(u8, addr_str, ". ");

    var ip_addr: u32 = 0;
    var count: u5 = 0;
    while(tokens.next()) |token| {
        const octet = std.fmt.parseInt(u8, token, 10) catch { return IpError.IpIncorrectError; };
        const place: u5 = 3 - count;
        ip_addr += @as(u32, octet) << (place * 8);
        count += 1;
    }

    if(count != 4) {
        return IpError.IpIncorrectError;
    }

    ip_addr = std.mem.nativeToBig(u32, ip_addr);

    return ip_addr;
}

pub fn networkPort(comptime port: u16) u16 {
    return std.mem.nativeToBig(u16, port);
}

test "ip address is properly converted into an int" {
    try std.testing.expectEqual(ipAddr("127.0.0.1") catch unreachable, std.mem.nativeToBig(u32, 2130706433));
}

test "port is correctly put into network endianness" {
    try std.testing.expectEqual(networkPort(7890), std.mem.nativeToBig(u16, 7890));
}
