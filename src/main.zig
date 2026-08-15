const std = @import("std");
const Io = std.Io;
const libnest = @import("libnest");
const cova = @import("cova");
const toml = @import("toml");
const config = @import("config/config.zig");

const CommandT = cova.Command.Custom(.{});
const OptionT = CommandT.OptionT;
const ValueT = CommandT.ValueT;

const root_cmd: CommandT = .{
    .name = "nest",
    .description = "",
    .sub_cmds = &.{
        CommandT{
            .name = "sync",
            .description = "Sync the package repositories and update their indexes",
        },
    },
};

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
        try libnest.repo.RepoConn.open(&ctx, repo);
    }

    const store_conn = try libnest.store.newConn(ctx);
    defer store_conn.close();
}
