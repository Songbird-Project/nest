const std = @import("std");
const libnest = @import("libnest");
const Ctx = libnest.context.Context;
const config = @import("config/config.zig");
const Cfg = config.Config;
const sets = @import("sets.zig");

fn getGenForActivation(ctx: Ctx, profile_id: i64, gen_num: ?i64) !i64 {
    var target = if (gen_num) |num|
        num
    else
        libnest.store.generation.getLatest(ctx, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for system profile\n", .{});
                std.process.exit(10);
            },
            else => return err,
        };

    if (target < 0) {
        const latest = libnest.store.generation.getCurrent(ctx, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for system profile\n", .{});
                std.process.exit(10);
            },
            else => return err,
        };
        target = latest + target;
    }

    if (target < 0) {
        try ctx.log(
            .Error,
            "Cannot rollback to generation {d}, negative generations are not possible\n",
            .{target},
        );
        std.process.exit(11);
    }

    return target;
}

fn getOrCreateProfile(ctx: Ctx, name: []const u8) !i64 {
    return libnest.store.profile.getId(
        ctx,
        name,
    ) catch |err| switch (err) {
        error.ProfileNotFound => return libnest.store.profile.new(ctx, name),
        else => return err,
    };
}

pub fn activateGen(
    ctx: Ctx,
    user: ?[]const u8,
    gen_num: ?i64,
) !void {
    const profile_id = try getOrCreateProfile(ctx, user orelse "system");
    const target = try getGenForActivation(ctx, profile_id, gen_num);

    const gen_id = libnest.store.generation.getId(
        ctx,
        profile_id,
        target,
    ) catch |err| switch (err) {
        error.GenerationNotFound => {
            try ctx.log(
                .Error,
                "Generation {d} for profile '{s}' not found\n",
                .{ target, user orelse "system" },
            );
            std.process.exit(32);
        },
        else => return err,
    };
    try libnest.store.generation.activate(ctx, gen_id);
}

pub fn sync(
    ctx: Ctx,
    repos: []const []const u8,
) !void {
    for (ctx.repos.items) |repo| {
        var skip = true;
        for (repos) |r| {
            if (std.mem.eql(u8, r, repo.repo.name)) {
                skip = false;
                break;
            }
        }
        if (repos.len == 0) skip = false;
        if (skip) continue;
        try libnest.sync.syncRepo(ctx, repo.*);
    }
}

pub fn activate(ctx: Ctx, cfg: Cfg, user: ?[]const u8, generation: ?i64) !void {
    if (user) |u| {
        if (std.mem.eql(u8, u, "all")) for (cfg.users) |us| {
            try activateGen(ctx, us.name.item, null);
        };
        try activateGen(ctx, null, null);
    } else {
        try activateGen(ctx, user, generation);
    }
}

fn appendSet(
    ctx: Ctx,
    packages: *std.ArrayList([]const u8),
    name: []const u8,
) !bool {
    inline for (.{ sets.pkg, sets.driver, sets.firmware }) |set| {
        inline for (comptime std.meta.declarations(set)) |decl| {
            const field = @field(set, decl.name);
            const info = @typeInfo(@TypeOf(field));

            if (info != .array or info.array.child != []const u8) continue;
            if (std.mem.eql(u8, decl.name, name)) {
                try packages.appendSlice(ctx.alloc, &field);
                return true;
            }
        }
    }
    return false;
}

pub fn build(ctx: Ctx, cfg: Cfg, should_activate: bool) !void {
    const profile_id = libnest.store.profile.getId(ctx, "system") catch |err| switch (err) {
        error.ProfileNotFound => try libnest.store.profile.new(ctx, "system"),
        else => return err,
    };

    var packages: std.ArrayList([]const u8) = .empty;
    defer packages.deinit(ctx.alloc);
    for (cfg.pkgs) |tagged| {
        if (tagged.is("aur") and !cfg.aur) continue;

        if (tagged.is("set")) {
            if (try appendSet(ctx, &packages, tagged.item)) continue;
            try ctx.log(.Warn, "Unrecognized package set: {s}\n", .{tagged.item});
            continue;
        }

        try packages.append(ctx.alloc, tagged.item);
    }

    const pkgs = try libnest.repo.getProviderWithDepsAll(ctx, packages.items, null);
    defer {
        for (pkgs) |pkg| pkg.deinit(ctx.alloc);
        ctx.alloc.free(pkgs);
    }
    try libnest.sync.syncPackages(ctx, pkgs);

    const gen_id = try libnest.store.generation.new(ctx, profile_id);
    try libnest.store.generation.build(ctx, gen_id, pkgs);

    if (should_activate) try activateGen(ctx, null, null);
}

pub fn purge(ctx: Ctx, cfg: Cfg, user: ?[]const u8, older: ?u32) !void {
    if (user != null and std.mem.eql(u8, user.?, "all")) {
        for (cfg.users) |us| {
            const profile_id = try getOrCreateProfile(ctx, us.name.item);
            const older_than: u32 = if (older) |num| num else @intCast(libnest.store.generation.getCurrent(
                ctx,
                profile_id,
            ) catch |err| switch (err) {
                error.NoGenerations => {
                    try ctx.log(.Error, "No generations found for profile '{s}'\n", .{us.name.item});
                    std.process.exit(10);
                },
                else => return err,
            });

            try libnest.store.generation.purgeAll(
                ctx,
                profile_id,
                older_than,
            );
        }
        const profile_id = try getOrCreateProfile(ctx, "system");
        const older_than: u32 = if (older) |num| num else @intCast(libnest.store.generation.getCurrent(
            ctx,
            profile_id,
        ) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for system profile\n", .{});
                std.process.exit(10);
            },
            else => return err,
        });

        try libnest.store.generation.purgeAll(
            ctx,
            profile_id,
            older_than,
        );
    } else {
        const profile_id = try getOrCreateProfile(ctx, user orelse "system");
        const older_than: u32 = if (older) |num| num else @intCast(libnest.store.generation.getCurrent(
            ctx,
            profile_id,
        ) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{user orelse "system"});
                std.process.exit(10);
            },
            else => return err,
        });

        try libnest.store.generation.purgeAll(
            ctx,
            profile_id,
            older_than,
        );
    }
}
