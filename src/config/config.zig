const std = @import("std");
const Allocator = std.mem.Allocator;
const libnest = @import("libnest");
const Ctx = libnest.context.Context;
const luajit = @import("luajit");
const lua = @import("lua.zig");
const tags = @import("../tags.zig");

const SystemConfig = struct {
    aur: bool,
    bootloader: []const u8,
    profile: []const u8,
    kernels: [][]const u8,
    services: [][]const u8,
    packages: []tags.TaggedItem,

    pub fn deinit(self: *SystemConfig, alloc: Allocator) void {
        alloc.free(self.bootloader);
        alloc.free(self.profile);
        for (self.kernels) |kernel| alloc.free(kernel);
        alloc.free(self.kernels);
        for (self.services) |service| alloc.free(service);
        alloc.free(self.services);
        for (self.packages) |package| alloc.free(package);
        alloc.free(self.packages);
    }
};

const Profile = struct {
    name: tags.TaggedItem,
    packages: []tags.TaggedItem,

    pub fn deinit(self: *Profile, alloc: Allocator) void {
        alloc.free(self.name);
        for (self.packages) |package| alloc.free(package);
        alloc.free(self.packages);
    }
};

pub const Config = struct {
    repos: []libnest.repo.Repo,
    system: SystemConfig,
    profiles: []Profile,

    pub fn init(ctx: Ctx, path: []const u8) !Config {
        const state = try lua.init(ctx.alloc);
        defer state.deinit();

        try lua.loadFile(ctx, state, path);
        _ = state.getGlobal("nest");
        defer state.pop(1);

        var config = try getConfig(ctx.alloc, state);
        errdefer config.deinit(ctx.alloc);

        return config;
    }

    pub fn deinit(self: *Config, alloc: Allocator) void {
        for (self.repos) |repo| {
            for (repo.mirrors) |mirror| alloc.free(mirror);
            alloc.free(repo.mirrors);

            alloc.free(repo.name);
            alloc.free(repo.arch);
        }
        alloc.free(self.repos);

        for (self.profiles) |*profile| profile.deinit(alloc);
        alloc.free(self.profiles);

        self.system.deinit(alloc);
    }
};

fn getConfig(alloc: Allocator, state: *lua.Lua) !Config {
    return .{
        .system = try lua.withField(state, SystemConfig, alloc, readSystemConfig, -1, "system"),
        .profiles = try lua.withField(state, []Profile, alloc, readProfiles, -1, "profiles"),
        .repos = try lua.withField(state, []libnest.repo.Repo, alloc, readRepos, -1, "repos"),
    };
}

fn readSystemConfig(alloc: Allocator, state: *lua.Lua, idx: i32) !SystemConfig {
    const table_idx = lua.absIndex(state, idx);
    return .{
        .aur = try lua.withField(state, bool, alloc, lua.readBool, table_idx, "aur"),
        .profile = try lua.withField(state, []const u8, alloc, lua.dupeString, table_idx, "profile"),
        .bootloader = try lua.withOptionalField(
            state,
            []const u8,
            alloc,
            lua.dupeString,
            table_idx,
            "bootloader",
            defaultBootloader,
        ),
        .kernels = try lua.withOptionalField(
            state,
            [][]const u8,
            alloc,
            lua.getStringArray,
            table_idx,
            "kernels",
            defaultKernels,
        ),
        .services = try lua.withOptionalField(
            state,
            [][]const u8,
            alloc,
            lua.getStringArray,
            table_idx,
            "services",
            defaultEmptyArrayAlloc,
        ),
        .packages = try lua.withOptionalField(
            state,
            []tags.TaggedItem,
            alloc,
            getTaggedArray,
            table_idx,
            "packages",
            defaultPackages,
        ),
    };
}

fn readProfiles(alloc: Allocator, state: *lua.Lua, idx: i32) ![]Profile {
    return try lua.getArray(alloc, state, Profile, readProfile, idx);
}

fn readProfile(alloc: Allocator, state: *lua.Lua, idx: i32) !Profile {
    const table_idx = lua.absIndex(state, idx);
    return .{
        .name = blk: {
            _ = state.getTableIndexRaw(idx, 1);
            defer state.pop(1);
            break :blk try tags.parse(alloc, try lua.getString(state, -1));
        },
        .packages = try lua.withOptionalField(
            state,
            []tags.TaggedItem,
            alloc,
            getTaggedArray,
            table_idx,
            "packages",
            defaultEmptyTagsArray,
        ),
    };
}

fn readRepos(alloc: Allocator, state: *lua.Lua, idx: i32) ![]libnest.repo.Repo {
    return lua.getArray(alloc, state, libnest.repo.Repo, readRepo, idx);
}

fn readRepo(alloc: Allocator, state: *lua.Lua, idx: i32) !libnest.repo.Repo {
    const table_idx = lua.absIndex(state, idx);
    return .{
        .name = blk: {
            _ = state.getTableIndexRaw(idx, 1);
            defer state.pop(1);
            break :blk try lua.dupeString(alloc, state, -1);
        },
        .arch = try lua.withOptionalField(state, []const u8, alloc, lua.dupeString, table_idx, "arch", defaultArch),
        .mirrors = try lua.withField(state, [][]const u8, alloc, lua.getStringArray, table_idx, "mirrors"),
    };
}

// Ctx-based bridges

fn getString(ctx: Ctx, state: *lua.Lua, idx: i32) ![]const u8 {
    return lua.dupeString(ctx.alloc, state, idx);
}

fn getStringArray(ctx: Ctx, state: *lua.Lua, idx: i32) ![][]const u8 {
    return lua.getStringArray(ctx.alloc, state, idx);
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

// Defaults for config fields

fn defaultBootloader(alloc: Allocator) ![]const u8 {
    return try alloc.dupe(u8, "grub");
}

fn defaultKernels(alloc: Allocator) ![][]const u8 {
    const list = try alloc.alloc([]const u8, 1);
    list[0] = try alloc.dupe(u8, "linux");
    return list;
}

fn defaultPackages(alloc: Allocator) ![]tags.TaggedItem {
    const list = try alloc.alloc(tags.TaggedItem, 1);
    list[0] = try tags.parse(alloc, "coreutils");
    return list;
}

fn defaultArch(alloc: Allocator) ![]const u8 {
    return try alloc.dupe(u8, "any");
}

fn defaultEmptyArray(_: Ctx) ![][]const u8 {
    return &.{};
}

fn defaultEmptyArrayAlloc(_: Allocator) ![][]const u8 {
    return &.{};
}

fn defaultEmptyTagsArray(_: Allocator) ![]tags.TaggedItem {
    return &.{};
}
