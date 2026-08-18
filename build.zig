const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_c = b.addTranslateC(.{
        .root_source_file = b.path("lib/lua.h"),
        .target = target,
        .optimize = optimize,
    });
    lua_c.linkSystemLibrary("lua", .{});

    const exe = b.addExecutable(.{
        .name = "nest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{
                    .name = "lua_c",
                    .module = lua_c.createModule(),
                },
            },
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

    b.installArtifact(exe);
    b.installFile("resources/nest.lua", "usr/share/nest/nest.lua");
    b.installFile("resources/luarc.json", "etc/nest/.luarc.json");
}
