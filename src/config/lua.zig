// SPDX-FileCopyrightText: 2025-2026 Songbird Project
//
// SPDX-License-Identifier: BSD-3-Clause

const std = @import("std");
const Io = std.Io;
const Alloc = std.mem.Allocator;
const zlua = @import("zlua");
pub const Lua = zlua.Lua;

pub const Ctx = struct {
    io: Io,
    alloc: Alloc,
    dir: []const u8,

    pub fn init(io: Io, alloc: Alloc, path: []const u8) Ctx {
        return .{ .io = io, .alloc = alloc, .dir = Io.Dir.path.dirname(path) orelse "." };
    }
};

pub fn setup(ctx: *Ctx, lua: *Lua) void {
    lua.openTable();
    lua.openMath();
    lua.openString();
    lua.openUtf8();

    lua.newTable();
    lua.pushLightUserdata(ctx);
    lua.pushClosure(zlua.wrap(lua_readlines), 1);
    lua.setField(-2, "readlines");
    lua.setGlobal("nest");

    lua.newTable();
    lua.setGlobal("pkg");

    lua.newTable();
    lua.setGlobal("system");

    lua.newTable();
    lua.setGlobal("iso");
}

fn lua_readlines(lua: *Lua) i32 {
    const rel = lua.toString(1) catch lua.raiseErrorStr("Expected string for path", .{});

    const ctx = lua.toUserdata(Ctx, Lua.upvalueIndex(1)) catch
        lua.raiseErrorStr("Invalid upvalue", .{});

    const path = (if (Io.Dir.path.isAbsolute(rel))
        ctx.alloc.dupe(u8, rel)
    else
        Io.Dir.path.join(ctx.alloc, &.{ ctx.dir, rel })) catch
        lua.raiseErrorStr("out of memory", .{});
    defer ctx.alloc.free(path);

    const contents = Io.Dir.cwd().readFileAlloc(
        ctx.io,
        path,
        ctx.alloc,
        .unlimited,
    ) catch |err| lua.raiseErrorStr("Failed to read file {s}: {s}", .{ path, @errorName(err) });
    defer ctx.alloc.free(contents);

    lua.newTable();

    var i: i32 = 0;
    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line| {
        const trim = std.mem.trim(u8, line, " \r\t");
        if (trim.len == 0) continue;
        i += 1;
        _ = lua.pushString(trim);
        lua.setIndex(-2, i);
    }

    return 1;
}
