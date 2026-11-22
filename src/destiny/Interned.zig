const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @This();

pub const Handle = enum(u32) { _ };

allocator: Allocator,
text: std.ArrayList(u8) = .empty,
index: std.ArrayList(u32) = .empty,
seen: std.hash_map.HashMapUnmanaged(Handle, void, Interned, 80) = .empty,

pub fn init(allocator: Allocator) Allocator.Error!Interned {
    var self: Interned = .{ .allocator = allocator };
    try self.index.append(allocator, 0);
    return self;
}

pub fn deinit(self: *Interned) void {
    self.text.deinit(self.allocator);
    self.index.deinit(self.allocator);
    self.seen.deinit(self.allocator);
}

pub fn hash(self: *const Interned, value: Handle) u64 {
    return std.hash.Wyhash.hash(0, self.get(value));
}

pub fn eql(self: *const Interned, a: Handle, b: Handle) bool {
    return std.mem.eql(u8, self.get(a), self.get(b));
}

pub fn internSlice(self: *Interned, str: []const u8) Allocator.Error!Handle {
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
        @fromBackingInt(@intCast(index_limit)),
        self.*,
    );

    if (slot.found_existing) {
        // Undo the text/index append
        self.text.items.len = text_limit;
        self.index.items.len = index_limit;
    }

    return slot.key_ptr.*;
}

pub fn get(self: *const Interned, handle: Handle) []const u8 {
    const id = @backingInt(handle);
    assert(id != 0);
    const ix = self.index.items;
    return self.text.items[ix[id - 1]..ix[id]];
}

test Interned {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();

    const one = try int.internSlice("one");
    try std.testing.expectEqual(1, @backingInt(one));
    try std.testing.expectEqualDeep("one", int.get(one));
    const two = try int.internSlice("two woohoo");
    try std.testing.expectEqual(2, @backingInt(two));
    try std.testing.expectEqualDeep("two woohoo", int.get(two));
    const another_one = try int.internSlice("one");
    try std.testing.expectEqual(1, @backingInt(another_one));
    try std.testing.expectEqualDeep("one", int.get(another_one));
}
