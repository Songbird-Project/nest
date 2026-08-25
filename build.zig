const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .use_llvm = true,
    });
    const libnest = b.dependency("libnest", .{
        .target = target,
        .optimize = optimize,
        .config = "libnest.zon",
    });
    exe.root_module.addImport("libnest", libnest.module("libnest"));
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("clap", clap.module("clap"));
    const luajit = b.dependency("luajit", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("luajit", luajit.module("luajit"));

    b.installArtifact(exe);
    b.installFile("resources/nest.lua", "usr/share/nest/nest.lua");
    b.installFile("resources/luarc.json", "etc/nest/.luarc.json");
}
