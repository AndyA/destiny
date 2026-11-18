const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @This();

allocator: Allocator,
text: std.ArrayList(u8) = .empty,
index: std.ArrayList(u32) = .empty,
seen: std.hash_map.HashMapUnmanaged(u32, void, Interned, 80) = .empty,

pub fn init(gpa: Allocator) Allocator.Error!Interned {
    var self: Interned = .{ .allocator = gpa };
    try self.index.append(gpa, 0);
    return self;
}

pub fn deinit(self: *Interned) void {
    self.text.deinit(self.allocator);
    self.index.deinit(self.allocator);
    self.seen.deinit(self.allocator);
}

pub fn hash(self: *const Interned, value: u32) u64 {
    return std.hash.Wyhash.hash(0, self.get(value));
}

pub fn eql(self: *const Interned, a: u32, b: u32) bool {
    return std.mem.eql(u8, self.get(a), self.get(b));
}

pub fn intern(self: *Interned, str: []const u8) Allocator.Error!u32 {
    const text_limit = self.text.items.len;
    const index_limit = self.index.items.len;
    errdefer {
        self.text.items.len = text_limit;
        self.index.items.len = index_limit;
    }

    try self.text.appendSlice(self.allocator, str);
    try self.index.append(self.allocator, @intCast(self.text.items.len));

    const slot = try self.seen.getOrPutContext(
        self.allocator,
        @intCast(index_limit),
        self.*,
    );

    if (slot.found_existing) {
        // Undo the text/index append
        self.text.items.len = text_limit;
        self.index.items.len = index_limit;
    }

    return slot.key_ptr.*;
}

pub fn get(self: *const Interned, id: u32) []const u8 {
    assert(id != 0);
    const ix = self.index.items;
    return self.text.items[ix[id - 1]..ix[id]];
}

test Interned {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();

    const one = try int.intern("one");
    try std.testing.expectEqual(1, one);
    try std.testing.expectEqualDeep("one", int.get(one));
    const two = try int.intern("two woohoo");
    try std.testing.expectEqual(2, two);
    try std.testing.expectEqualDeep("two woohoo", int.get(two));
    const another_one = try int.intern("one");
    try std.testing.expectEqual(1, another_one);
    try std.testing.expectEqualDeep("one", int.get(another_one));
}
