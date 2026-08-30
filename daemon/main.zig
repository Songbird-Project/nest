const std = @import("std");
const Io = std.Io;
const libnest = @import("libnest");
const Ctx = libnest.context.Context;
const config = @import("config/config.zig");
const Cfg = config.Config;
const ops = @import("operations.zig");

pub const SOCKET_PATH = "/run/nest/nestd.sock";

pub const Request = union(enum) {
    sync: struct { repos: []const []const u8 = &.{} },
    build: struct { user: ?[]const u8, activate: bool = false },
    activate: struct { user: ?[]const u8, generation: ?i64 = null },
    purge: struct { user: ?[]const u8, older_than: ?u32 = null },
    search: struct { query: []const u8 },

    pub fn isMutating(self: Request) bool {
        return switch (self) {
            .sync, .build, .activate, .purge => true,
            .search => false,
        };
    }
};

pub const Response = union(enum) {
    log: struct { level: []const u8, msg: []const u8 },
    select: struct { count: usize },
    done: struct { status: []const u8, err: ?[]const u8 = null },
};

const Daemon = struct {
    ctx: *Ctx,
    queue: Io.Queue(*QueueItem),
};

const QueueItem = struct {
    req: Request,
    done: Io.Event,
    result: anyerror!void = undefined,
    reader: *Io.Reader,
    writer: *Io.Writer,
};

const ActiveConn = struct {
    alloc: std.mem.Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
};

var active_conn: ActiveConn = undefined;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    var threaded_io: Io.Threaded = .init(alloc, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    try Io.Dir.cwd().createDirPath(io, Io.Dir.path.dirname(SOCKET_PATH).?);

    Io.Dir.cwd().deleteFile(io, SOCKET_PATH) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    const addr = try Io.net.UnixAddress.init(SOCKET_PATH);
    var server = try addr.listen(io, .{});
    defer server.deinit(io);

    try Io.Dir.cwd().setFilePermissions(io, SOCKET_PATH, .fromMode(0o660), .{});

    var ctx: Ctx = .init(alloc, io);
    defer ctx.deinit();
    ctx.store = try libnest.store.open(ctx);
    ctx.log_options = .{
        .minimum_log_level = .Info,
        .debug_prefix = "",
        .info_prefix = "",
        .warn_prefix = "",
        .error_prefix = "",
        .fatal_prefix = "",
    };

    const queue_buf = try alloc.alloc(*QueueItem, 16);
    defer alloc.free(queue_buf);
    var daemon: Daemon = .{ .ctx = &ctx, .queue = Io.Queue(*QueueItem).init(queue_buf) };
    defer daemon.queue.close(io);

    var async_worker = io.async(worker, .{ io, &daemon });
    defer async_worker.cancel(io) catch {};

    var conns: Io.Group = .init;
    defer conns.cancel(io);

    while (true) {
        const stream = try server.accept(io);
        conns.async(io, handleConn, .{ io, stream, &daemon });
    }
}

fn handleConn(io: Io, stream: Io.net.Stream, daemon: *Daemon) void {
    handleConnFailing(io, stream, daemon) catch |err|
        daemon.ctx.log(.Error, "Connection failed: {}\n", .{err}) catch {};
}

fn handleConnFailing(io: Io, stream: Io.net.Stream, daemon: *Daemon) !void {
    defer stream.close(io);

    var reader_buf: [8192]u8 = undefined;
    var reader = stream.reader(io, &reader_buf);
    var writer_buf: [8192]u8 = undefined;
    var writer = stream.writer(io, &writer_buf);

    const line = try reader.interface.takeDelimiter('\n') orelse return;
    const parsed = try std.json.parseFromSlice(Request, daemon.ctx.alloc, line, .{});
    defer parsed.deinit();
    const req = parsed.value;

    if (req.isMutating()) {
        var item: QueueItem = .{
            .req = req,
            .done = .waiting,
            .reader = &reader.interface,
            .writer = &writer.interface,
        };
        try daemon.queue.putOne(io, &item);
        try item.done.wait(io);
        try sendDone(&writer.interface, item.result);
    } else {
        const result = dispatch(io, daemon.ctx, req, &writer.interface);
        try sendDone(&writer.interface, result);
    }
}

fn sendDone(writer: *Io.Writer, result: anyerror!void) !void {
    var stringify: std.json.Stringify = .{ .writer = writer };
    if (result) |_| {
        try stringify.write(Response{ .done = .{ .status = "ok" } });
    } else |err| {
        try stringify.write(Response{ .done = .{ .status = "error", .err = @errorName(err) } });
    }
    try writer.writeByte('\n');
    try writer.flush();
}

fn dispatch(io: Io, ctx: *Ctx, req: Request, writer: *Io.Writer) !void {
    _ = io;
    _ = ctx;
    _ = req;
    _ = writer;
}

fn dispatchBlocking(ctx: *Ctx, req: Request) !void {
    const alloc = ctx.alloc;

    const cfg_path = try Io.Dir.path.join(alloc, &.{
        ctx.path_options.root,
        ctx.path_options.config,
        "config.lua",
    });
    defer alloc.free(cfg_path);

    var cfg: Cfg = try .init(ctx.*, cfg_path);
    defer cfg.deinit(alloc);

    ctx.select_cb = selectCb;
    ctx.log_cb = logCb;

    const mirrors = try cfg.sourcesToMirrors(alloc);
    defer alloc.free(mirrors);
    try libnest.repo.openAll(ctx, mirrors);
    defer ctx.closeRepoConns();

    try switch (req) {
        .sync => |s| ops.sync(ctx.*, s.repos),
        .build => |b| ops.build(ctx.*, cfg, b.activate),
        .activate => |a| ops.activate(ctx.*, cfg, a.user, a.generation),
        .search => unreachable,
        else => @panic("not ready"),
    };
}

fn worker(io: Io, daemon: *Daemon) !void {
    while (true) {
        const item = daemon.queue.getOne(io) catch break;

        active_conn = .{
            .alloc = daemon.ctx.alloc,
            .reader = item.reader,
            .writer = item.writer,
        };

        item.result = dispatchBlocking(daemon.ctx, item.req);
        item.done.set(io);
    }
}

fn logCb(io: Io, level: libnest.context.LogLevel, msg: []const u8) anyerror!void {
    _ = io;
    var stringify: std.json.Stringify = .{ .writer = active_conn.writer };
    try stringify.write(Response{ .log = .{ .level = @tagName(level), .msg = msg } });
    try active_conn.writer.writeByte('\n');
    try active_conn.writer.flush();
}

fn selectCb(io: Io, count: usize) !usize {
    _ = io;
    var stringify: std.json.Stringify = .{ .writer = active_conn.writer };
    try stringify.write(Response{ .select = .{ .count = count } });
    try active_conn.writer.writeByte('\n');
    try active_conn.writer.flush();

    const line = try active_conn.reader.takeDelimiter('\n') orelse return error.ConnectionClosed;
    const Reply = struct { selected: usize };
    const parsed = try std.json.parseFromSlice(Reply, active_conn.alloc, line, .{});
    defer parsed.deinit();
    return parsed.value.selected;
}
