const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const InternedStrings = struct {
    const Self = @This();

    text: std.ArrayList(u8) = .empty,
    index: std.ArrayList(u32) = .empty,
    lookup: std.StringHashMapUnmanaged(u32) = .empty,
    allocator: Allocator,

    pub fn init(gpa: Allocator) Allocator.Error!Self {
        var self: Self = .{ .allocator = gpa };
        try self.index.append(gpa, 0);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit(self.allocator);
        self.index.deinit(self.allocator);
        self.lookup.deinit(self.allocator);
    }

    pub fn intern(self: *Self, str: []const u8) Allocator.Error!u32 {
        const slot = try self.lookup.getOrPut(self.allocator, str);
        if (slot.found_existing)
            return slot.value_ptr.*;
        try self.text.appendSlice(self.allocator, str);
        const id: u32 = @intCast(self.index.items.len);
        try self.index.append(self.allocator, @intCast(self.text.items.len));
        slot.value_ptr.* = id;
        return id;
    }

    pub fn get(self: *const Self, id: u32) []const u8 {
        assert(id != 0);
        const index = self.index.items;
        return self.text.items[index[id - 1]..index[id]];
    }
};

test InternedStrings {
    var int: InternedStrings = try .init(std.testing.allocator);
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

pub const Pathname = struct {
    name: u32,
    parent: u32,
};

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
