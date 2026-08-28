const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TaggedItem = struct {
    item: []const u8,
    tags: std.StringHashMap(void),

    pub fn deinit(self: *TaggedItem, alloc: Allocator) void {
        alloc.free(self.item);
        var it = self.tags.keyIterator();
        while (it.next()) |tag| alloc.free(tag.*);
        self.tags.deinit();
    }

    pub fn is(self: TaggedItem, kind: []const u8) bool {
        if (self.tags.getKey(kind) != null) return true;
        return false;
    }
};

pub fn parse(alloc: Allocator, to_parse: []const u8) !TaggedItem {
    var result: TaggedItem = .{
        .item = undefined,
        .tags = undefined,
    };

    result.tags = .init(alloc);
    errdefer {
        var it = result.tags.keyIterator();
        while (it.next()) |tag| alloc.free(tag.*);
        result.tags.deinit();
    }

    var it = std.mem.splitScalar(u8, to_parse, '`');
    while (it.next()) |tag| {
        if (it.index == null or it.index.? == 0) {
            result.item = try alloc.dupe(u8, tag);
            continue;
        }

        try result.tags.put(try alloc.dupe(u8, tag), {});
    }

    return result;
}
