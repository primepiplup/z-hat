const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const client = b.addExecutable(.{
    	.name = "client",
    	.root_source_file = .{ .path = "client.zig" },
		.target = target,
		.optimize = optimize,
    });

    const server = b.addExecutable(.{
        .name = "server",
        .root_source_file = .{ .path = "server.zig" },
        .target = target,
        .optimize = optimize,
    });

    client.linkLibC();
    client.linkSystemLibrary("curses");

    const server_inst = b.addInstallArtifact(server, .{});
    const client_inst = b.addInstallArtifact(client, .{});

    const client_step = b.step("client", "Build the client");
    const server_step = b.step("server", "Build the server");

    client_step.dependOn(&client_inst.step);
    server_step.dependOn(&server_inst.step);

    const run_server = b.addRunArtifact(server);
    const run_client = b.addRunArtifact(client);

    const run_server_step = b.step("run_server", "Run the server");
    run_server_step.dependOn(&server_inst.step);
    run_server_step.dependOn(&run_server.step);

    const run_client_step = b.step("run_client", "Run the client");
    run_client_step.dependOn(&client_inst.step);
    run_client_step.dependOn(&run_client.step);
}
