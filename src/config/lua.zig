const std = @import("std");
const Allocator = std.mem.Allocator;
const libnest = @import("libnest");
const Ctx = libnest.context.Context;
const luajit = @import("luajit");

pub const Lua = luajit.Lua;

pub fn init(alloc: Allocator) !*Lua {
    const lua = try Lua.init(alloc);
    lua.openLibs();
    try registerAPI(lua);

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

fn registerAPI(lua: *Lua) !void {
    lua.createTable(0, 16);
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

pub fn getString(lua: *Lua, idx: i32) ![]const u8 {
    return try lua.toLString(idx);
}
