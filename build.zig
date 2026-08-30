const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libnest = b.dependency("libnest", .{
        .target = target,
        .optimize = optimize,
        .name = "nest",
    });
    const luajit = b.dependency("luajit", .{ .target = target, .optimize = optimize });
    const clap = b.dependency("clap", .{ .target = target, .optimize = optimize });

    const daemon = b.addExecutable(.{
        .name = "nestd",
        .root_module = b.createModule(.{
            .root_source_file = b.path("daemon/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .use_llvm = true,
    });
    daemon.root_module.addImport("luajit", luajit.module("luajit"));
    daemon.root_module.addImport("libnest", libnest.module("libnest"));

    const cli = b.addExecutable(.{
        .name = "nest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{
                    .name = "daemon",
                    .module = daemon.root_module,
                },
            },
        }),
        .use_llvm = true,
    });
    cli.root_module.addImport("clap", clap.module("clap"));

    b.installArtifact(cli);
    b.installArtifact(daemon);
    b.installFile("resources/nest.lua", "usr/share/nest/nest.lua");
    b.installFile("resources/luarc.json", "etc/nest/.luarc.json");
}
