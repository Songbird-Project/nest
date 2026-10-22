const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libnest = b.dependency("libnest", .{
        .target = target,
        .optimize = optimize,
        .name = "nest",
    });
    const zlua = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
        .lang = .lua54,
        .shared = true,
    });
    const clap = b.dependency("clap", .{ .target = target, .optimize = optimize });

    const cli = b.addExecutable(.{
        .name = "nest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .use_llvm = true,
    });
    cli.root_module.addImport("libnest", libnest.module("libnest"));
    cli.root_module.addImport("zlua", zlua.module("zlua"));
    cli.root_module.addImport("clap", clap.module("clap"));

    b.installArtifact(cli);
    b.installFile("resources/nest.lua", "usr/share/nest/nest.lua");
    b.installFile("resources/luarc.json", "etc/nest/.luarc.json");
}
