// SPDX-FileCopyrightText: 2025-2026 Songbird Project
//
// SPDX-License-Identifier: BSD-3-Clause

const std = @import("std");
const Alloc = std.mem.Allocator;
const Io = std.Io;
const lua = @import("lua.zig");

const json = @embedFile("../lua/json.lua");
const encode = @embedFile("../lua/encode.lua");

pub const Nest = struct {
    autoclean: Autoclean = .{},

    pub const Autoclean = struct {
        enabled: bool = true,
        when: []const u8 = "48h",
        keep: u32 = 3,
    };
};

pub const Pkg = struct {
    sources: Sources = .{},
    pkgs: Pkgs = .{},

    pub const Toggle = struct { enabled: bool = true };
    pub const Pkgbuild = struct {
        enabled: bool = false,
        source: ?[]const u8 = null,
    };
    pub const Source = struct {
        enabled: bool = true,
        priority: u32 = 999,
        mirrors: []const []const u8 = &.{},
    };
    pub const Sources = struct {
        aur: Toggle = .{ .enabled = false },
        pkgbuild: ?Pkgbuild = null,
        repo: std.json.ArrayHashMap(Source) = .{},
    };
    pub const Pkgs = struct {
        repo: []const []const u8 = &.{},
        aur: []const []const u8 = &.{},
        pkgbuild: []const []const u8 = &.{},
    };
};

pub const System = struct {
    enable: bool = false,

    info: Info = .{},
    boot: Boot = .{},
    users: std.json.ArrayHashMap(User) = .{},
    services: Services = .{},
    files: std.json.ArrayHashMap(File) = .{},

    pub const Info = struct {
        locale: ?[]const u8 = null,
        hostname: ?[]const u8 = null,
        timezone: ?[]const u8 = null,
    };

    pub const Bootloader = enum { grub };
    pub const Boot = struct {
        loader: Bootloader = .grub,
        kernels: []const []const u8 = &.{},
        timeout: u32 = 3,
    };

    pub const User = struct {
        system: bool = false,
        home: ?[]const u8 = null,
        create_home: ?bool = null,
        extra_groups: []const []const u8 = &.{},
        shell: ?[]const u8 = null,
    };

    pub const Manager = enum { systemd };
    pub const Scopes = struct {
        system: []const []const u8 = &.{},
        users: std.json.ArrayHashMap([]const []const u8) = .{},
    };
    pub const Services = struct {
        manager: Manager = .systemd,
        enable: Scopes = .{},
        disable: Scopes = .{},
        mask: Scopes = .{},
    };

    pub const File = struct {
        source: []const u8,
        mode: enum { copy, symlink, hardlink } = .copy,
        owner: ?[]const u8 = null,
        parents: bool = false,
    };
};

pub const Config = struct {
    nest: Nest = .{},
    pkg: Pkg = .{},
    system: System = .{},
};

const setup =
    \\pkg.sources = { repo = {} }
    \\pkg.pkgs = {}
    \\system.info = {}
    \\system.boot = {}
    \\system.users = {}
    \\system.files = {}
    \\local function scopes() return { system = {}, users = {} } end
    \\system.services = { enable = scopes(), disable = scopes(), mask = scopes() }
;

pub fn parse(io: Io, alloc: Alloc, path: []const u8) !std.json.Parsed(Config) {
    const l = try lua.Lua.init(alloc);
    defer l.deinit();

    var ctx: lua.Ctx = .init(io, alloc, path);
    lua.setup(&ctx, l);
    try l.doString(setup);

    const pathz = try alloc.dupeSentinel(u8, path, 0);
    defer alloc.free(pathz);
    l.doFile(pathz) catch |err| {
        std.log.err("config: {s}", .{l.toString(-1) catch @errorName(err)});
        return err;
    };

    try l.doString(json);
    l.setGlobal("json");
    l.doString(encode) catch |err| {
        std.log.err("encode: {s}", .{l.toString(-1) catch @errorName(err)});
        return err;
    };
    defer l.pop(1);

    const text = try l.toString(-1);
    return std.json.parseFromSlice(Config, alloc, text, .{
        .allocate = .alloc_always,
    });
}
