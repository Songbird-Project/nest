const std = @import("std");
const Allocator = std.mem.Allocator;
const libnest = @import("libnest");
pub const c = @import("lua_c");

pub fn init() !*c.lua_State {
    const L = c.luaL_newstate();
    if (L == null) return error.LuaInitFailed;
    c.luaL_openlibs(L);

    const lua: *c.lua_State = L.?;
    registerAPI(lua);

    return lua;
}

pub fn deinit(state: *c.lua_State) void {
    c.lua_close(state);
}

pub fn loadFile(ctx: libnest.context.Context, state: *c.lua_State, path: []const u8) !void {
    const path_z = try ctx.alloc.dupeSentinel(u8, path, 0);
    defer ctx.alloc.free(path_z);

    if (c.luaL_loadfilex(state, path_z.ptr, null) != 0) {
        const err = c.lua_tolstring(state, -1, null);
        if (err != null) {
            try ctx.log(
                .Error,
                "Lua failed to load file '{s}' with error: {s}\n",
                .{ path, std.mem.span(err) },
            );
        }
        c.lua_settop(state, -2);
        return error.LuaLoadFile;
    }

    if (c.lua_pcallk(state, 0, 0, 0, 0, null) != 0) {
        const err = c.lua_tolstring(state, -1, null);
        if (err != null) {
            try ctx.log(
                .Error,
                "Lua runtime error in '{s}' with error: {s}\n",
                .{ path, std.mem.span(err) },
            );
        }
        c.lua_settop(state, -2);
        return error.LuaRuntime;
    }
}

fn registerAPI(state: *c.lua_State) void {
    c.lua_createtable(state, 0, 16);

    c.lua_setglobal(state, "nest");
}

pub fn dupeString(alloc: Allocator, state: *c.lua_State, idx: c_int) ![]const u8 {
    var len: usize = 0;
    const ptr = c.lua_tolstring(state, idx, &len);
    if (ptr == null) return error.LuaNotString;
    return try alloc.dupe(u8, ptr[0..len]);
}

pub fn getStringArray(alloc: Allocator, state: *c.lua_State, table_idx: c_int) ![][]const u8 {
    const idx = c.lua_absindex(state, table_idx);
    const len = c.lua_rawlen(state, idx);

    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |val| alloc.free(val);
        list.deinit(alloc);
    }

    var i: c_int = 1;
    while (i <= @as(c_int, @intCast(len))) : (i += 1) {
        _ = c.lua_rawgeti(state, idx, i);
        const val = try dupeString(alloc, state, -1);
        c.lua_settop(state, -2);
        try list.append(alloc, val);
    }

    return try list.toOwnedSlice(alloc);
}
