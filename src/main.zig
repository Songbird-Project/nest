const std = @import("std");
const Io = std.Io;
const libnest = @import("libnest");
const cova = @import("cova");
const config = @import("config/config.zig");

const CommandT = cova.Command.Custom(.{
    .global_help_prefix = "nest - A Declarative Arch Package Manager",
});
const OptionT = CommandT.OptionT;
const ValueT = CommandT.ValueT;

const root_cmd: CommandT = .{
    .name = "nest",
    .description = "A Declarative Arch Package Manager",
    .sub_cmds = &.{
        CommandT{
            .name = "sync",
            .description = "Sync package databases with their remotes",
            .examples = &.{ "nest sync --repos=core,extra", "nest sync" },
            .opts = &.{
                OptionT{
                    .name = "repos",
                    .description = "Only sync the given databases",
                    .long_name = "repos",
                    .short_name = 'r',
                    .val = ValueT.ofType(
                        []const u8,
                        .{
                            .name = "repo",
                            .description = "Repo to sync",
                        },
                    ),
                },
            },
        },
    },
};

pub fn main(init: std.process.Init) !void {
    var stdout_buf: [256]u8 = undefined;
    var writer = Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &writer.interface;

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
        try libnest.repo.RepoConn.open(&ctx, repo);
    }

    const store_conn = try libnest.store.newConn(ctx);
    defer store_conn.close();

    var main_cmd = try root_cmd.init(init.gpa, .{});
    defer main_cmd.deinit();

    var arg_iter: cova.ArgIteratorGeneric = try .init(init.gpa, init.minimal.args);
    defer arg_iter.deinit();

    cova.parseArgs(
        &arg_iter,
        CommandT,
        main_cmd,
        stdout,
        .{},
    ) catch |err| switch (err) {
        error.UsageHelpCalled,
        error.TooManyValues,
        error.UnrecognizedArgument,
        error.UnexpectedArgument,
        error.CouldNotParseOption,
        => return,
        else => return err,
    };

    if (main_cmd.matchSubCmd("sync")) |sync_cmd| {
        var repo_it = ctx.repos.iterator();
        const repos: ?[][]const u8 = opt: {
            if ((try sync_cmd.getOpts(.{})).get("repos")) |repos_opt| {
                if (repos_opt.val.isSet())
                    break :opt try repos_opt.val.getAs([][]const u8)
                else
                    break :opt null;
            }
            break :opt null;
        };

        while (repo_it.next()) |repo| {
            var skip = true;
            if (repos) |rs| {
                for (rs) |r| {
                    if (std.mem.eql(u8, r, repo.key_ptr.*)) {
                        skip = false;
                        break;
                    }
                }
            } else skip = false;
            if (skip) continue;
            try libnest.sync.syncRepo(ctx, repo.value_ptr.*);
        }
    }
}
