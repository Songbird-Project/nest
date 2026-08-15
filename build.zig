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
    const cova = b.dependency("cova", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("cova", cova.module("cova"));
    const toml = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("toml", toml.module("toml"));

    b.installArtifact(exe);
}
