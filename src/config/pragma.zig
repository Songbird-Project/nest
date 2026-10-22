const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Cfg = @import("config.zig").Config;

const PREFIX = "--@pragma";

const flags: std.StaticStringMap(void) = .initComptime(.{
    .{ "system", {} },
});

const Pragma = union(enum) {
    flag: []const u8,
};

pub fn applyAll(io: Io, alloc: Allocator, cfg: *Cfg, path: []const u8) !void {
    const src = try Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(src);

    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, PREFIX)) continue;

        const expr = std.mem.trim(u8, trimmed[PREFIX.len..], " \t");
        var toks = std.mem.splitScalar(u8, expr, '=');

        const name = toks.next() orelse continue;
        if (flags.has(name)) setOpts(cfg, .{ .flag = name });
    }
}

pub fn setOpts(cfg: *Cfg, pragma: Pragma) void {
    switch (pragma) {
        .flag => |f| {
            if (std.mem.eql(u8, f, "system")) cfg.opts.system = true;
        },
    }
}
