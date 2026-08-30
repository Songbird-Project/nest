const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const libnest = @import("libnest");
const Ctx = libnest.context.Context;
const luajit = @import("luajit");
const lua = @import("lua.zig");
const tags = @import("../tags.zig");

const pks_sets = struct {
    const essential = [_][]const u8{
        "bash",
        "coreutils",
        "filesystem",
        "gcc-libs",
        "glibc",
        "gzip",
        "shadow",
        "util-linux",
    };

    const core = [_][]const u8{
        "archlinux-keyring",
        "gawk",
        "grep",
        "sed",
    };

    const systemd = [_][]const u8{
        "systemd",
        "systemd-sysvcompat",
    };

    const sys_utils = [_][]const u8{
        "file",
        "findutils",
        "pciutils",
        "procps-ng",
        "psmisc",
    };

    const net_utils = [_][]const u8{
        "iputils",
        "iproute2",
        "networkmanager",
    };

    const archive_utils = [_][]const u8{
        "bzip2",
        "tar",
        "xz",
        "zstd",
    };
};

const User = struct {
    name: tags.TaggedItem,
    groups: [][]const u8,
    home: []const u8,
    pkgs: []tags.TaggedItem,

    pub fn deinit(self: *User, alloc: Allocator) void {
        self.name.deinit(alloc);
        alloc.free(self.home);
        for (self.pkgs) |*package| package.deinit(alloc);
        alloc.free(self.pkgs);
    }
};

const Source = struct {
    name: []const u8,
    priority: i64,
    mirrors: [][]const u8,

    pub fn deinit(self: *Source, alloc: Allocator) void {
        alloc.free(self.name);
        for (self.mirrors) |mirror| alloc.free(mirror);
        alloc.free(self.mirrors);
    }
};

const Sets = struct {
    core: bool = true,
    systemd: bool = true,
    sys_utils: bool = true,
    net_utils: bool = true,
    archive_utils: bool = true,
};

pub const Config = struct {
    aur: bool,
    arch: []const u8,

    bootloader: []const u8,
    hostname: []const u8,
    timezone: []const u8,
    locale: []const u8,

    kernels: []tags.TaggedItem,
    services: [][]const u8,
    pkgs: []tags.TaggedItem,

    pkg_sets: Sets,
    sources: []Source,
    users: []User,

    pub fn init(ctx: Ctx, path: []const u8) !Config {
        const state = try lua.init(ctx.alloc);
        defer state.deinit();

        try lua.loadFile(ctx, state, path);
        _ = state.getGlobal("system");
        defer state.pop(1);

        var config = try getConfig(ctx.alloc, state);
        errdefer config.deinit(ctx.alloc);

        var sys_pkgs: std.ArrayList(tags.TaggedItem) = .empty;
        errdefer {
            for (sys_pkgs.items) |*pkg| pkg.deinit(ctx.alloc);
            sys_pkgs.deinit(ctx.alloc);
        }

        for (pks_sets.essential) |pkg| try sys_pkgs.append(ctx.alloc, try tags.parse(ctx.alloc, pkg));
        if (config.pkg_sets.core) for (pks_sets.core) |pkg| try sys_pkgs.append(
            ctx.alloc,
            try tags.parse(ctx.alloc, pkg),
        );
        if (config.pkg_sets.systemd) for (pks_sets.systemd) |pkg| try sys_pkgs.append(
            ctx.alloc,
            try tags.parse(ctx.alloc, pkg),
        );
        if (config.pkg_sets.sys_utils) for (pks_sets.sys_utils) |pkg| try sys_pkgs.append(
            ctx.alloc,
            try tags.parse(ctx.alloc, pkg),
        );
        if (config.pkg_sets.net_utils) for (pks_sets.net_utils) |pkg| try sys_pkgs.append(
            ctx.alloc,
            try tags.parse(ctx.alloc, pkg),
        );
        if (config.pkg_sets.archive_utils) for (pks_sets.archive_utils) |pkg| try sys_pkgs.append(
            ctx.alloc,
            try tags.parse(ctx.alloc, pkg),
        );
        for (config.kernels) |kernel| try sys_pkgs.append(ctx.alloc, kernel);

        return config;
    }

    pub fn deinit(self: *Config, alloc: Allocator) void {
        for (self.sources) |*source| source.deinit(alloc);
        alloc.free(self.sources);

        alloc.free(self.bootloader);
        alloc.free(self.hostname);
        alloc.free(self.timezone);
        alloc.free(self.locale);

        for (self.kernels) |*kernel| kernel.deinit(alloc);
        alloc.free(self.kernels);
        libnest.internal.mem.freeSlice(alloc, self.services);
        for (self.pkgs) |*pkg| pkg.deinit(alloc);
        alloc.free(self.pkgs);

        for (self.users) |*user| user.deinit(alloc);
        alloc.free(self.users);
    }

    pub fn sourcesToMirrors(self: *Config, alloc: Allocator) ![]libnest.repo.Repo {
        var repos: std.ArrayList(libnest.repo.Repo) = .empty;
        errdefer repos.deinit(alloc);
        for (self.sources) |source| try repos.append(alloc, .{
            .name = source.name,
            .arch = self.arch,
            .priority = source.priority,
            .mirrors = source.mirrors,
        });

        return try repos.toOwnedSlice(alloc);
    }
};

fn getConfig(alloc: Allocator, state: *lua.Lua) !Config {
    return .{
        .aur = try lua.withField(state, bool, alloc, lua.readBool, -1, "aur"),
        .arch = try withStringField(state, alloc, -1, "arch") orelse try alloc.dupe(u8, "x86_64"),
        .bootloader = try withStringField(state, alloc, -1, "bootloader") orelse try alloc.dupe(u8, "grub"),
        .hostname = try withStringField(state, alloc, -1, "hostname") orelse try alloc.dupe(u8, "localhost"),
        .locale = try withStringField(state, alloc, -1, "locale") orelse try alloc.dupe(u8, "en_US.UTF-8"),
        .timezone = try withStringField(state, alloc, -1, "timezone") orelse try alloc.dupe(u8, "UTC"),

        .kernels = try lua.withNullableField(state, []tags.TaggedItem, alloc, getTaggedArray, -1, "kernels") orelse &.{},
        .services = try withStringArrayField(state, alloc, -1, "services") orelse &.{},
        .pkgs = try lua.withNullableField(
            state,
            []tags.TaggedItem,
            alloc,
            getTaggedArray,
            -1,
            "pkgs",
        ) orelse &.{},

        .pkg_sets = try lua.withNullableField(state, Sets, alloc, readSets, -1, "pkg_sets") orelse .{},
        .sources = try lua.withNullableField(
            state,
            []Source,
            alloc,
            readSources,
            -1,
            "sources",
        ) orelse &.{},
        .users = try lua.withNullableField(
            state,
            []User,
            alloc,
            readUsers,
            -1,
            "users",
        ) orelse &.{},
    };
}

fn readSets(alloc: Allocator, state: *lua.Lua, idx: i32) !Sets {
    const table_idx = lua.absIndex(state, idx);
    return .{
        .core = try lua.withNullableField(state, bool, alloc, lua.readBool, table_idx, "core") orelse true,
        .systemd = try lua.withNullableField(state, bool, alloc, lua.readBool, table_idx, "systemd") orelse true,
        .sys_utils = try lua.withNullableField(state, bool, alloc, lua.readBool, table_idx, "sys_utils") orelse true,
        .net_utils = try lua.withNullableField(state, bool, alloc, lua.readBool, table_idx, "net_utils") orelse true,
        .archive_utils = try lua.withNullableField(state, bool, alloc, lua.readBool, table_idx, "archive_utils") orelse true,
    };
}

fn readUsers(alloc: Allocator, state: *lua.Lua, idx: i32) ![]User {
    return try lua.getArray(alloc, state, User, readUser, idx);
}

fn readUser(alloc: Allocator, state: *lua.Lua, idx: i32) !User {
    const table_idx = lua.absIndex(state, idx);
    const name = blk: {
        _ = state.getTableIndexRaw(idx, 1);
        defer state.pop(1);
        break :blk try tags.parse(alloc, try lua.getString(state, -1));
    };

    return .{
        .name = name,
        .home = try withStringField(state, alloc, table_idx, "home") orelse try Io.Dir.path.join(alloc, &.{ "/home", name.item }),
        .groups = try withStringArrayField(state, alloc, table_idx, "groups") orelse &.{},
        .pkgs = try lua.withNullableField(
            state,
            []tags.TaggedItem,
            alloc,
            getTaggedArray,
            table_idx,
            "packages",
        ) orelse &.{},
    };
}

fn readSources(alloc: Allocator, state: *lua.Lua, idx: i32) ![]Source {
    return lua.getArray(alloc, state, Source, readSource, idx);
}

fn readSource(alloc: Allocator, state: *lua.Lua, idx: i32) !Source {
    const table_idx = lua.absIndex(state, idx);
    return .{
        .name = blk: {
            _ = state.getTableIndexRaw(idx, 1);
            defer state.pop(1);
            break :blk try lua.dupeString(alloc, state, -1);
        },
        .priority = try lua.withField(state, i64, alloc, lua.readInt, table_idx, "priority"),
        .mirrors = try withStringArrayField(state, alloc, table_idx, "mirrors") orelse &.{},
    };
}

// Helpers
fn withStringField(
    state: *lua.Lua,
    alloc: Allocator,
    table_idx: i32,
    field: [:0]const u8,
) !?[]const u8 {
    return try lua.withNullableField(
        state,
        []const u8,
        alloc,
        lua.dupeString,
        table_idx,
        field,
    );
}

fn withStringArrayField(
    state: *lua.Lua,
    alloc: Allocator,
    table_idx: i32,
    field: [:0]const u8,
) !?[][]const u8 {
    return try lua.withNullableField(
        state,
        [][]const u8,
        alloc,
        lua.getStringArray,
        table_idx,
        field,
    );
}

// custom get functions

pub fn getTaggedArray(
    alloc: Allocator,
    state: *lua.Lua,
    table_idx: i32,
) ![]tags.TaggedItem {
    const idx = lua.absIndex(state, table_idx);
    const len = state.getLength(idx);

    var list: std.ArrayList(tags.TaggedItem) = .empty;
    errdefer {
        for (list.items) |*tag| tag.deinit(alloc);
        list.deinit(alloc);
    }

    var i: i32 = 1;
    while (i <= len) : (i += 1) {
        _ = state.getTableIndexRaw(idx, i);
        defer state.pop(1);
        try list.append(alloc, try tags.parse(alloc, try lua.getString(state, -1)));
    }

    return try list.toOwnedSlice(alloc);
}
