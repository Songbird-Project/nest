const std = @import("std");
const Allocator = std.mem.Allocator;
const libnest = @import("libnest");
const lua = @import("lua.zig");
const c = lua.c;

pub const Config = struct {
    repos: []libnest.repo.Repo,
    packages: []const []const u8,

    pub fn init(ctx: libnest.context.Context, path: []const u8) !Config {
        const state = try lua.init();
        defer lua.deinit(state);

        try lua.loadFile(ctx, state, path);

        return try getConfig(ctx.alloc, state);
    }

    pub fn deinit(self: *Config, alloc: Allocator) void {
        for (self.repos) |repo| {
            for (repo.mirrors) |mirror| alloc.free(mirror);
            alloc.free(repo.mirrors);

            alloc.free(repo.name);
            alloc.free(repo.arch);
        }
        alloc.free(self.repos);

        for (self.packages) |package| alloc.free(package);
        alloc.free(self.packages);
    }
};

fn getConfig(alloc: Allocator, state: *c.lua_State) !Config {
    _ = c.lua_getglobal(state, "nest");
    defer c.lua_settop(state, -2);

    _ = c.lua_getfield(state, -1, "repos");
    const repos = try getRepoList(alloc, state, -1);
    defer c.lua_settop(state, -2);

    _ = c.lua_getfield(state, -1, "packages");
    const packages = try lua.getStringArray(alloc, state, -1);
    defer c.lua_settop(state, -2);

    return .{ .repos = repos, .packages = packages };
}

fn getRepo(alloc: Allocator, state: *c.lua_State, table_idx: c_int) !libnest.repo.Repo {
    const idx = c.lua_absindex(state, table_idx);

    _ = c.lua_rawgeti(state, idx, 1);
    const name = try lua.dupeString(alloc, state, -1);
    c.lua_settop(state, -2);

    _ = c.lua_getfield(state, idx, "arch");
    const arch = try lua.dupeString(alloc, state, -1);
    c.lua_settop(state, -2);

    _ = c.lua_getfield(state, idx, "mirrors");
    const mirrors = try lua.getStringArray(alloc, state, -1);
    c.lua_settop(state, -2);

    return .{
        .name = name,
        .arch = arch,
        .mirrors = mirrors,
    };
}

fn getRepoList(alloc: Allocator, state: *c.lua_State, table_idx: c_int) ![]libnest.repo.Repo {
    const idx = c.lua_absindex(state, table_idx);
    const n = c.lua_rawlen(state, idx);

    var list = try std.ArrayList(libnest.repo.Repo).initCapacity(alloc, n);
    errdefer list.deinit(alloc);

    var i: c_int = 1;
    while (i <= @as(c_int, @intCast(n))) : (i += 1) {
        _ = c.lua_rawgeti(state, idx, i);
        const repo = try getRepo(alloc, state, -1);
        c.lua_settop(state, -2);
        try list.append(alloc, repo);
    }
    return list.toOwnedSlice(alloc);
}
