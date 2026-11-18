const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @import("Interned.zig");

const Self = @This();
pub const PathElement = struct {
    parent: u32,
    name: u32,

    pub fn hash(self: *const @This()) u64 {
        var hasher: std.hash.Wyhash = .init(0);
        std.hash.autoHash(&hasher, self);
        return hasher.final();
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return self.parent == other.parent and
            self.name == other.name;
    }
};

pub const ROOT: u32 = 0;

allocator: Allocator,
int: *Interned,
paths: std.ArrayList(PathElement) = .empty,
seen: std.hash_map.HashMapUnmanaged(u32, void, Self, 80) = .empty,

pub fn init(allocator: Allocator, int: *Interned) Allocator.Error!Self {
    var self: Self = .{ .allocator = allocator, .int = int };
    // Root element always present
    try self.paths.append(self.allocator, .{ .name = 0, .parent = ROOT });
    return self;
}

pub fn deinit(self: *Self) void {
    self.paths.deinit(self.allocator);
    self.seen.deinit(self.allocator);
}

pub fn hash(self: *const Self, id: u32) u64 {
    return self.get(id).hash();
}

pub fn eql(self: *const Self, a: u32, b: u32) bool {
    return self.get(a).eql(self.get(b));
}

pub fn get(self: *const Self, id: u32) PathElement {
    return self.paths.items[id];
}

pub fn getElementName(self: *const Self, id: u32) []const u8 {
    return self.int.get(self.get(id).name);
}

pub fn intern(self: *Self, parent: u32, name: []const u8) Allocator.Error!u32 {
    const paths_limit = self.paths.items.len;
    errdefer self.paths.items.len = paths_limit;

    try self.paths.append(self.allocator, .{
        .name = try self.int.intern(name),
        .parent = parent,
    });

    const slot = try self.seen.getOrPutContext(
        self.allocator,
        @intCast(paths_limit),
        self.*,
    );

    if (slot.found_existing)
        self.paths.items.len = paths_limit;

    return slot.key_ptr.*;
}

test "Pathnames" {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Self = try .init(std.testing.allocator, &int);
    defer paths.deinit();

    const usr_id = try paths.intern(ROOT, "usr");
    try std.testing.expectEqual(1, usr_id);
    try std.testing.expectEqualDeep("usr", paths.getElementName(usr_id));

    const local_id = try paths.intern(usr_id, "local");
    try std.testing.expectEqual(2, local_id);

    const share_id = try paths.intern(local_id, "share");
    try std.testing.expectEqual(3, share_id);

    const bin_id = try paths.intern(local_id, "bin");
    try std.testing.expectEqual(4, bin_id);

    const another_local_id = try paths.intern(usr_id, "local");
    try std.testing.expectEqual(2, another_local_id);
}
