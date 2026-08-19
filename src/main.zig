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
    var ctx: libnest.context.Context = .init(init.gpa, init.io);
    defer ctx.deinit();

    ctx.path_options = .{ .root = "./test" };

    const cfg_path = try Io.Dir.path.join(init.gpa, &.{
        ctx.path_options.root,
        ctx.path_options.config,
        "config.lua",
    });
    defer init.gpa.free(cfg_path);

    var cfg: config.Config = try .init(ctx, cfg_path);
    defer cfg.deinit(init.gpa);

    for (cfg.repos) |repo| {
        libnest.repo.RepoConn.open(&ctx, repo) catch |err| switch (err) {
            error.NoMirrors => std.process.exit(57),
            else => return err,
        };
    }

    const store_conn = try libnest.store.newConn(ctx);
    defer store_conn.close();

    var iter = try init.minimal.args.iterateAllocator(init.gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parser, &iter, .{
        .allocator = init.gpa,
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
        .build => build(ctx, cfg, &iter, store_conn),
        .activate => activate(ctx, cfg, &iter, store_conn),
        .rollback => activate_gen(ctx, cfg, -1, store_conn),
        .purge => purge(ctx, cfg, &iter, store_conn),
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

fn activate(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator, store_conn: libnest.store.StoreConn) !void {
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
        store_conn,
    );
}

fn activate_gen(
    ctx: libnest.context.Context,
    cfg: config.Config,
    gen_num: ?i64,
    store_conn: libnest.store.StoreConn,
) !void {
    const profile_id = libnest.store.profile.getId(
        store_conn,
        cfg.profile,
    ) catch |err| switch (err) {
        error.ProfileNotFound => try libnest.store.profile.new(store_conn, cfg.profile),
        else => return err,
    };

    var target: i64 = undefined;
    if (gen_num == null)
        target = libnest.store.generation.getLatest(store_conn, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.profile});
                std.process.exit(10);
            },
            else => return err,
        };

    target = gen_num.?;
    if (target < 0) {
        const latest = libnest.store.generation.getCurrent(store_conn, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.profile});
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
        store_conn,
        profile_id,
        target,
    ) catch |err| switch (err) {
        error.GenerationNotFound => {
            try ctx.log(
                .Error,
                "Generation {d} for profile '{s}' not found\n",
                .{ target, cfg.profile },
            );
            std.process.exit(32);
        },
        else => return err,
    };
    try libnest.store.generation.activate(ctx, store_conn, gen_id);
}

fn build(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator, store_conn: libnest.store.StoreConn) !void {
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

    var providers: std.ArrayList(libnest.package.Provider) = .empty;
    defer {
        for (providers.items) |provider| provider.deinit(ctx.alloc);
        providers.deinit(ctx.alloc);
    }

    for (cfg.packages) |pkg| {
        const pkgs = try libnest.repo.getProviderWithDeps(ctx, pkg, null);
        defer ctx.alloc.free(pkgs);
        try providers.appendSlice(ctx.alloc, pkgs);
    }

    try libnest.sync.syncPackages(ctx, store_conn, providers.items);
    if (res.args.activate != 0) try activate_gen(ctx, cfg, 0, store_conn);
}

fn purge(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator, store_conn: libnest.store.StoreConn) !void {
    const profile_id = libnest.store.profile.getId(
        store_conn,
        cfg.profile,
    ) catch |err| switch (err) {
        error.ProfileNotFound => try libnest.store.profile.new(store_conn, cfg.profile),
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
        @intCast(libnest.store.generation.getCurrent(store_conn, profile_id) catch |err| switch (err) {
            error.NoGenerations => {
                try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.profile});
                std.process.exit(10);
            },
            else => return err,
        });

    try libnest.store.generation.purgeAll(
        ctx,
        store_conn,
        profile_id,
        older_than,
    );
}
