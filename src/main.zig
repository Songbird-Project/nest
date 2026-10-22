const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zlua = @import("zlua");
const clap = @import("clap");
const daemon = @import("daemon/daemon.zig");

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
    \\    --daemon      Start nest in daemon mode
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

    if (res.args.daemon != 0)
        daemon.start(init);

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
        .rollback => rollback(io, alloc, &iter, &writer.interface),
        else => @panic("not ready"),
        // .purge => purge(ctx, cfg, &iter),
    };

    try recieveResponse(io, alloc, &reader.interface);
}

fn sendRequest(writer: *Io.Writer, req: daemon.Request) !void {
    var stringify: std.json.Stringify = .{ .writer = writer };
    try stringify.write(req);
    try writer.writeByte('\n');
    try writer.flush();
}

fn recieveResponse(io: Io, alloc: Allocator, reader: *Io.Reader) !void {
    while (true) {
        const line = try reader.takeDelimiter('\n') orelse return error.ConnClosed;

        const parsed = try std.json.parseFromSlice(daemon.Response, alloc, line, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        switch (parsed.value) {
            .log => |l| try log(io, l.level, l.msg),
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

fn rollback(io: Io, alloc: Allocator, iter: *Args.Iterator, writer: *Io.Writer) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
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

    const user = res.positionals[0];

    try sendRequest(writer, .{ .activate = .{ .user = user, .generation = -1 } });
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

fn purge(io: Io, alloc: Allocator, iter: *Args.Iterator, writer: *Io.Writer) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit
        \\<str>
        \\<usize>
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

    const user = res.positionals[0];
    const older_than = res.positionals[1];

    try sendRequest(writer, .{ .purge = .{ .user = user, .older_than = older_than } });
}
