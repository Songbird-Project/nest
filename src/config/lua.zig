const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const libnest = @import("libnest");
const Ctx = libnest.context.Context;
const luajit = @import("luajit");

pub const Lua = luajit.Lua;

pub fn init(ctx: Ctx) !*Lua {
    const lua = try Lua.init(ctx.alloc);
    lua.openLibs();
    try registerAPI(&ctx, lua);

    return lua;
}

pub fn loadFile(ctx: Ctx, lua: *Lua, path: []const u8) !void {
    const path_z = try ctx.alloc.dupeSentinel(u8, path, 0);
    defer ctx.alloc.free(path_z);
    lua.doFile(path_z) catch |err| {
        const msg = lua.toString(-1) catch "unknown error";
        try ctx.log(.Error, "Lua error in '{s}', {s}\n", .{ path, msg });
        lua.pop(1);
        return err;
    };
}

fn registerAPI(ctx: *const Ctx, lua: *Lua) !void {
    lua.newTable();
    lua.setGlobal("system");

    lua.newTable();

    lua.pushLightUserdata(@constCast(ctx));
    lua.pushCClosure(luaReadLines, 1);
    lua.setField(-2, "read_lines");

    lua.setGlobal("nest");
}

pub fn dupeString(alloc: Allocator, lua: *Lua, idx: i32) ![]const u8 {
    const s = try lua.toLString(idx);
    return try alloc.dupe(u8, s);
}

pub fn absIndex(lua: *Lua, idx: i32) i32 {
    if (idx < 0) return lua.getTop() + idx + 1;
    return idx;
}

pub fn withField(
    lua: *Lua,
    comptime T: type,
    ctx: anytype,
    comptime read: fn (@TypeOf(ctx), *Lua, i32) anyerror!T,
    table_idx: i32,
    field: [:0]const u8,
) !T {
    _ = lua.getField(table_idx, field);
    defer lua.pop(1);
    return try read(ctx, lua, -1);
}

pub fn withOptionalField(
    lua: *Lua,
    comptime T: type,
    ctx: anytype,
    comptime read: fn (@TypeOf(ctx), *Lua, i32) anyerror!T,
    table_idx: i32,
    field: [:0]const u8,
    comptime makeDefault: fn (@TypeOf(ctx)) anyerror!T,
) !T {
    _ = lua.getField(table_idx, field);
    defer lua.pop(1);
    if (lua.isNil(-1)) return try makeDefault(ctx);
    return try read(ctx, lua, -1);
}

pub fn withNullableField(
    lua: *Lua,
    comptime T: type,
    ctx: anytype,
    comptime read: fn (@TypeOf(ctx), *Lua, i32) anyerror!T,
    table_idx: i32,
    field: [:0]const u8,
) !?T {
    _ = lua.getField(table_idx, field);
    defer lua.pop(1);
    if (lua.isNil(-1)) return null;
    return try read(ctx, lua, -1);
}

fn hasDeinit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "deinit"),
        else => false,
    };
}

pub fn getArray(
    alloc: Allocator,
    lua: *Lua,
    comptime T: type,
    comptime readItem: fn (Allocator, *Lua, i32) anyerror!T,
    table_idx: i32,
) ![]T {
    const idx = absIndex(lua, table_idx);
    const len = lua.getLength(idx);

    var list: std.ArrayList(T) = .empty;
    errdefer {
        for (list.items) |*item| {
            if (comptime hasDeinit(T)) item.deinit(alloc);
        }
        list.deinit(alloc);
    }

    var i: i32 = 1;
    while (i <= len) : (i += 1) {
        _ = lua.getTableIndexRaw(idx, i);
        defer lua.pop(1);
        try list.append(alloc, try readItem(alloc, lua, -1));
    }

    return try list.toOwnedSlice(alloc);
}

pub fn getStringArray(alloc: Allocator, lua: *Lua, table_idx: i32) ![][]const u8 {
    return try getArray(alloc, lua, []const u8, dupeString, table_idx);
}

pub fn readBool(_: Allocator, lua: *Lua, idx: i32) !bool {
    return lua.toBoolean(idx);
}

pub fn readInt(_: Allocator, lua: *Lua, idx: i32) !i64 {
    return @intCast(lua.toInteger(idx));
}

pub fn getString(lua: *Lua, idx: i32) ![]const u8 {
    return try lua.toLString(idx);
}

// Exposed API
fn luaReadLines(lua: *Lua) callconv(.c) c_int {
    const raw = lua.toUserdata(-10002 - 1).?;
    const ctx: *const Ctx = @ptrCast(@alignCast(raw));

    const io = ctx.io;

    lua.newTable();

    const path = lua.toLString(1) catch return 1;

    const file = Io.Dir.cwd().openFile(io, path, .{}) catch |err| {
        ctx.log(.Error, "Failed to read file '{s}': {s}\n", .{ path, @errorName(err) }) catch return 1;
        return 1;
    };
    defer file.close(io);
    var rbuf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &rbuf);
    const reader = &file_reader.interface;

    var lbuf: [512]u8 = undefined;
    var idx: i32 = 1;
    while (true) {
        var lwriter = Io.Writer.fixed(&lbuf);
        const bytes_read = reader.streamDelimiter(&lwriter, '\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => {
                ctx.log(.Error, "Failed to read line in file '{s}': {s}\n", .{ path, @errorName(err) }) catch return 1;
                return 1;
            },
        };
        if (bytes_read == 0 and lwriter.buffered().len == 0) break;

        const line = std.mem.trim(u8, lwriter.buffered(), " \t\r");
        if (line.len == 0) continue;

        lua.pushLString(line);
        lua.setTableIndexRaw(-2, idx);
        idx += 1;
    }

    return 1;
}
