const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

fn ArenaArrayList(comptime T: type) type {
    return struct {
        const Self = @This();

        list: std.ArrayList(T) = .empty,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return .{ .list = .empty, .allocator = allocator };
        }

        pub fn used(self: Self) u32 {
            return @intCast(self.list.items.len);
        }

        pub fn append(self: *Self, item: T) Allocator.Error!u32 {
            const pos = self.used();
            try self.list.append(self.allocator, item);
            return pos;
        }

        pub fn appendSlice(self: *Self, items: []const T) Allocator.Error!u32 {
            const pos = self.used();
            try self.list.appendSlice(self.allocator, items);
            return pos;
        }
    };
}

test ArenaArrayList {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var aal: ArenaArrayList(u8) = .init(arena.allocator());
    const pos1 = try aal.appendSlice("Hello");
    try std.testing.expectEqual(0, pos1);
    const pos2 = try aal.appendSlice(", World");
    try std.testing.expectEqual(5, pos2);
    try std.testing.expectEqualDeep("Hello, World", aal.list.items);
}

pub const InternedStrings = struct {
    const Self = @This();

    text_arena: std.heap.ArenaAllocator,
    text: ArenaArrayList(u8) = undefined,

    index_arena: std.heap.ArenaAllocator,
    index: ArenaArrayList(u32) = undefined,

    lookup_arena: std.heap.ArenaAllocator,
    lookup: std.StringHashMap(u32) = undefined,

    pub fn init(gpa: Allocator) Allocator.Error!Self {
        var self: Self = .{
            .text_arena = .init(gpa),
            .index_arena = .init(gpa),
            .lookup_arena = .init(gpa),
        };
        self.text = .init(self.text_arena.allocator());
        self.index = .init(self.index_arena.allocator());
        self.lookup = .init(self.lookup_arena.allocator());

        _ = try self.index.append(0);
        _ = try self.intern("Bingo!");

        return self;
    }

    pub fn deinit(self: *const Self) void {
        self.text_arena.deinit();
        self.index_arena.deinit();
        self.lookup_arena.deinit();
    }

    pub fn intern(self: *Self, str: []const u8) Allocator.Error!u32 {
        const slot = try self.lookup.getOrPut(str);
        if (slot.found_existing)
            return slot.value_ptr.*;
        _ = try self.text.appendSlice(str);
        const id = try self.index.append(self.text.used());
        slot.value_ptr.* = id;
        return id;
    }

    pub fn get(self: Self, id: u32) []const u8 {
        assert(id != 0);
        const index = self.index.list.items;
        return self.text.list.items[index[id - 1]..index[id]];
    }
};

test InternedStrings {
    var int: InternedStrings = try .init(std.testing.allocator);
    defer int.deinit();

    const base = 2;

    const one = try int.intern("one");
    try std.testing.expectEqual(base + 0, one);
    try std.testing.expectEqualDeep("one", int.get(one));
    const two = try int.intern("two");
    try std.testing.expectEqual(base + 1, two);
    try std.testing.expectEqualDeep("two", int.get(two));
    const another_one = try int.intern("one");
    try std.testing.expectEqual(base + 0, another_one);
    try std.testing.expectEqualDeep("one", int.get(another_one));
}

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
