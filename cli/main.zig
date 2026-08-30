const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const clap = @import("clap");
const daemon = @import("daemon");

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

    var threaded: Io.Threaded = .init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();

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

    const addr = try Io.net.UnixAddress.init(daemon.SOCKET_PATH);
    const stream = try addr.connect(io);
    defer stream.close(io);

    var read_buf: [8192]u8 = undefined;
    var write_buf: [8192]u8 = undefined;
    var reader = stream.reader(io, &read_buf);
    var writer = stream.writer(io, &write_buf);

    const command = res.positionals[0] orelse return error.MissingCommand;
    try switch (command) {
        .help => return clap.helpToFile(init.io, .stderr(), clap.Help, &main_params, .{}),
        .sync => sync(io, alloc, &iter, &writer.interface),
        .build => build(io, alloc, &iter, &writer.interface),
        .activate => activate(io, alloc, &iter, &writer.interface),
        else => @panic("not ready"),
        // .build => build(ctx, cfg, &iter),
        // .activate => activate(ctx, cfg, &iter),
        // .rollback => activate_gen(ctx, cfg, -1),
        // .purge => purge(ctx, cfg, &iter),
    };

    try recieveResponse(io, alloc, &reader.interface, &writer.interface);
}

fn sendRequest(writer: *Io.Writer, req: daemon.Request) !void {
    var stringify: std.json.Stringify = .{ .writer = writer };
    try stringify.write(req);
    try writer.writeByte('\n');
    try writer.flush();
}

fn recieveResponse(io: Io, alloc: Allocator, reader: *Io.Reader, writer: *Io.Writer) !void {
    while (true) {
        const line = try reader.takeDelimiter('\n') orelse return error.ConnClosed;

        const parsed = try std.json.parseFromSlice(daemon.Response, alloc, line, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        switch (parsed.value) {
            .log => |l| try log(io, l.level, l.msg),
            .select => |s| {
                const idx = try select(io, s.count);
                var stringify: std.json.Stringify = .{ .writer = writer };
                try stringify.write(.{ .index = idx });
                try writer.writeByte('\n');
                try writer.flush();
            },
            .done => |d| {
                if (std.mem.eql(u8, d.status, "error")) {
                    std.log.err("nestd: {s}", .{d.err orelse "unknown error"});
                    return error.OperationFailed;
                }

                return;
            },
        }
    }
}

// This is effectively the default libnest log function but using strings and no Ctx
fn log(io: Io, level: []const u8, msg: []const u8) !void {
    var buf: [256]u8 = undefined;
    const file = if (std.mem.eql(u8, level, "Warn") or
        std.mem.eql(u8, level, "Error") or
        std.mem.eql(u8, level, "Fatal")) Io.File.stderr() else Io.File.stdout();

    const prefix =
        if (std.mem.eql(u8, level, "Debug"))
            "\x1B[0;34m[\x1B[0;37mD\x1B[0;34m]\x1B[0m "
        else if (std.mem.eql(u8, level, "Info"))
            "\x1B[0;34m[\x1B[0;32m*\x1B[0;34m]\x1B[0m "
        else if (std.mem.eql(u8, level, "Warn"))
            "\x1B[0;34m[\x1B[0;33mW\x1B[0;34m]\x1B[0m "
        else if (std.mem.eql(u8, level, "Error"))
            "\x1B[0;34m[\x1B[0;31mE\x1B[0;34m]\x1B[0m "
        else if (std.mem.eql(u8, level, "Fatal"))
            "\x1B[0;34m[\x1B[0;35mF\x1B[0;34m]\x1B[0m "
        else
            "";

    var w = file.writer(io, &buf);
    const writer = &w.interface;
    try writer.writeAll(prefix);
    try writer.writeAll(msg);
    try writer.flush();
}

fn select(io: Io, items: usize) !usize {
    if (items == 0) return 0;

    var stdin_buf: [16]u8 = undefined;
    const stdin_file = Io.File.stdin();

    var stdin_reader = stdin_file.reader(io, &stdin_buf);
    const stdin = &stdin_reader.interface;

    var stdout_buf: [256]u8 = undefined;
    const file = Io.File.stdout();
    var writer = file.writer(io, &stdout_buf);
    const w = &writer.interface;

    var buf: [16]u8 = undefined;
    var input = Io.Writer.fixed(&buf);

    while (true) {
        try w.print("Select [1-{d}]: ", .{items});
        try w.flush();

        input.end = 0;

        _ = try stdin.streamDelimiter(&input, '\n');
        const trimmed = std.mem.trim(u8, input.buffered(), " \t\r\n");

        const val = std.fmt.parseInt(usize, trimmed, 10) catch {
            _ = try stdin.discardRemaining();
            continue;
        };

        if (val == 0 or val > items) continue;
        return val - 1;
    }
}

fn sync(
    io: Io,
    alloc: Allocator,
    iter: *Args.Iterator,
    writer: *Io.Writer,
) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\-r, --repos <str>...   Only sync the given repos
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(io, .stderr(), clap.Help, &params, .{});

    try sendRequest(writer, .{ .sync = .{ .repos = res.args.repos } });
}

fn activate(io: Io, alloc: Allocator, iter: *Args.Iterator, writer: *Io.Writer) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\-g, --generation <isize>   The generation to activate
        \\<str>
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(io, .stderr(), clap.Help, &params, .{});

    const gen_num = if (res.args.generation) |num| num else null;
    const user = res.positionals[0];

    try sendRequest(writer, .{ .activate = .{ .user = user, .generation = gen_num } });
}

fn build(io: Io, alloc: Allocator, iter: *Args.Iterator, writer: *Io.Writer) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\-a, --activate   Activate the newly built generation
        \\<str>
    );

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .allocator = alloc,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.helpToFile(io, .stderr(), clap.Help, &params, .{});

    const should_activate = res.args.activate != 0;
    const user = res.positionals[0];

    try sendRequest(writer, .{ .build = .{ .user = user, .activate = should_activate } });
}

// fn purge(ctx: Ctx, cfg: Cfg, iter: *Args.Iterator) !void {
//     const profile_id = libnest.store.profile.getId(
//         ctx,
//         cfg.system.profile,
//     ) catch |err| switch (err) {
//         error.ProfileNotFound => try libnest.store.profile.new(ctx, cfg.system.profile),
//         else => return err,
//     };
//
//     const params = comptime clap.parseParamsComptime(
//         \\-h, --help        Display this help and exit
//         \\<usize>
//     );
//
//     var diag = clap.Diagnostic{};
//     var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
//         .allocator = ctx.alloc,
//         .diagnostic = &diag,
//     }) catch |err| {
//         try diag.reportToFile(ctx.io, .stderr(), err);
//         return err;
//     };
//     defer res.deinit();
//
//     if (res.args.help != 0)
//         return clap.helpToFile(ctx.io, .stderr(), clap.Help, &params, .{});
//
//     const older_than: u32 = if (res.positionals[0]) |num|
//         @intCast(num)
//     else
//         @intCast(libnest.store.generation.getCurrent(ctx, profile_id) catch |err| switch (err) {
//             error.NoGenerations => {
//                 try ctx.log(.Error, "No generations found for profile '{s}'\n", .{cfg.system.profile});
//                 std.process.exit(10);
//             },
//             else => return err,
//         });
//
//     try libnest.store.generation.purgeAll(
//         ctx,
//         profile_id,
//         older_than,
//     );
// }
