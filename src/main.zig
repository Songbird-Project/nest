const std = @import("std");
const Io = std.Io;
const libnest = @import("libnest");
const config = @import("config/config.zig");
const clap = @import("clap");

const Ctx = libnest.context.Context;
const Cfg = config.Config;
const Args = std.process.Args;

const Subcommands = enum {
    help,
    sync,
    build,
    activate,
    rollback,
    purge,
};
const main_parser = .{ .command = clap.parsers.enumeration(Subcommands) };
const main_params = clap.parseParamsComptime(
    \\-h, --help        Display this help and exit
    \\<command>
);
const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parser);

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var ctx: libnest.context.Context = .init(alloc, init.io, .{});
    defer ctx.deinit();

    const cfg_path = try Io.Dir.path.join(alloc, &.{
        ctx.path_options.root,
        ctx.path_options.config,
        "config.lua",
    });
    defer alloc.free(cfg_path);

    var cfg: config.Config = try .init(ctx, cfg_path);
    defer cfg.deinit(alloc);

    for (cfg.repos) |repo| {
        libnest.repo.RepoConn.open(&ctx, repo) catch |err| switch (err) {
            error.NoMirrors => std.process.exit(57),
            else => return err,
        };
    }

    var iter = try init.minimal.args.iterateAllocator(alloc);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parser, &iter, .{
        .allocator = alloc,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(init.io, .stderr(), clap.Help, &main_params, .{});

    const command = res.positionals[0] orelse return error.MissingCommand;
    try switch (command) {
        .help => return clap.helpToFile(init.io, .stderr(), clap.Help, &main_params, .{}),
        .sync => sync(ctx, &iter),
        .build => build(ctx, cfg, &iter),
        .activate => activate(ctx, cfg, &iter),
        .rollback => activate_gen(ctx, cfg, -1),
        .purge => purge(ctx, cfg, &iter),
    };
}

fn sync(
    ctx: libnest.context.Context,
    iter: *Args.Iterator,
) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\-r, --repos <str>...   Only sync the given repos
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = ctx.alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(ctx.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(ctx.io, .stderr(), clap.Help, &params, .{});

    var repo_it = ctx.repos.iterator();
    while (repo_it.next()) |repo| {
        var skip = true;
        for (res.args.repos) |r| {
            if (std.mem.eql(u8, r, repo.key_ptr.*)) {
                skip = false;
                break;
            }
        }
        if (res.args.repos.len == 0) skip = false;
        if (skip) continue;
        try libnest.sync.syncRepo(ctx, repo.value_ptr.*);
    }
}

fn activate(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\-g, --generation <isize>   The generation to activate
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = ctx.alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(ctx.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(ctx.io, .stderr(), clap.Help, &params, .{});

    const gen_num: ?i64 = if (res.args.generation) |num| num else null;
    try activate_gen(
        ctx,
        cfg,
        gen_num,
    );
}

fn activate_gen(
    ctx: libnest.context.Context,
    cfg: config.Config,
    gen_num: ?i64,
) !void {
    const profile_id = libnest.store.profile.getId(
        ctx,
        cfg.system.profile,
    ) catch |err| switch (err) {
        error.ProfileNotFound => try libnest.store.profile.new(ctx, cfg.system.profile),
        else => return err,
    };

    var target = if (gen_num) |num|
        num
    else
        libnest.store.generation.getLatest(ctx, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.system.profile});
                std.process.exit(10);
            },
            else => return err,
        };

    if (target < 0) {
        const latest = libnest.store.generation.getCurrent(ctx, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.system.profile});
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

    const gen_id = libnest.store.generation.getId(
        ctx,
        profile_id,
        target,
    ) catch |err| switch (err) {
        error.GenerationNotFound => {
            try ctx.log(
                .Error,
                "Generation {d} for profile '{s}' not found\n",
                .{ target, cfg.system.profile },
            );
            std.process.exit(32);
        },
        else => return err,
    };
    try libnest.store.generation.activate(ctx, gen_id);
}

fn build(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\-a, --activate   Activate the newly built generation
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = ctx.alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(ctx.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(ctx.io, .stderr(), clap.Help, &params, .{});

    var packages: std.ArrayList([]const u8) = .empty;
    defer packages.deinit(ctx.alloc);
    for (cfg.system.packages) |tagged| {
        if (tagged.is("aur") and !cfg.system.aur) continue;
        try packages.append(ctx.alloc, tagged.item);
    }
    for (cfg.profiles) |profile| {
        if (!std.mem.eql(u8, profile.name.item, cfg.system.profile)) continue;
        for (profile.packages) |tagged| {
            if (tagged.is("aur") and !cfg.system.aur) continue;
            try packages.append(ctx.alloc, tagged.item);
        }
        break;
    }

    const pkgs = try libnest.repo.getProviderWithDepsAll(ctx, packages.items, null);
    defer {
        for (pkgs) |pkg| pkg.deinit(ctx.alloc);
        ctx.alloc.free(pkgs);
    }

    try libnest.sync.syncPackages(ctx, pkgs);
    if (res.args.activate != 0) try activate_gen(ctx, cfg, null);
}

fn purge(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator) !void {
    const profile_id = libnest.store.profile.getId(
        ctx,
        cfg.system.profile,
    ) catch |err| switch (err) {
        error.ProfileNotFound => try libnest.store.profile.new(ctx, cfg.system.profile),
        else => return err,
    };

    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\<usize>
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = ctx.alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(ctx.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(ctx.io, .stderr(), clap.Help, &params, .{});

    const older_than: u32 = if (res.positionals[0]) |num|
        @intCast(num)
    else
        @intCast(libnest.store.generation.getCurrent(ctx, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.system.profile});
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
