const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @import("Interned.zig");

const Pathnames = @This();

pub const Handle = enum(u32) { _ };
pub const ROOT: Handle = @fromBackingInt(0);

pub const PathElement = struct {
    parent: Handle,
    name: Interned.Handle,

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

allocator: Allocator,
int: *Interned,
paths: std.ArrayList(PathElement) = .empty,
seen: std.hash_map.HashMapUnmanaged(Handle, void, Pathnames, 80) = .empty,

pub fn init(allocator: Allocator, int: *Interned) Allocator.Error!Pathnames {
    var self: Pathnames = .{ .allocator = allocator, .int = int };
    // Root element always present
    try self.paths.append(self.allocator, .{ .name = @fromBackingInt(0), .parent = ROOT });
    return self;
}

pub fn deinit(self: *Pathnames) void {
    self.paths.deinit(self.allocator);
    self.seen.deinit(self.allocator);
}

pub fn hash(self: *const Pathnames, handle: Handle) u64 {
    return self.get(handle).hash();
}

pub fn eql(self: *const Pathnames, a: Handle, b: Handle) bool {
    return self.get(a).eql(self.get(b));
}

pub fn get(self: *const Pathnames, handle: Handle) PathElement {
    return self.paths.items[@backingInt(handle)];
}

pub fn getElementName(self: *const Pathnames, handle: Handle) []const u8 {
    return self.int.get(self.get(handle).name);
}

pub fn internHandle(self: *Pathnames, parent: Handle, name: Interned.Handle) Allocator.Error!Handle {
    const paths_limit = self.paths.items.len;
    errdefer self.paths.items.len = paths_limit;
    const handle: Handle = @fromBackingInt(@intCast(paths_limit));

    try self.paths.append(self.allocator, .{ .name = name, .parent = parent });

    const slot = try self.seen.getOrPutContext(self.allocator, handle, self.*);

    if (slot.found_existing)
        self.paths.items.len = paths_limit;

    return slot.key_ptr.*;
}

pub fn intern(self: *Pathnames, parent: Handle, name: []const u8) Allocator.Error!Handle {
    return self.internHandle(parent, try self.int.intern(name));
}

test Pathnames {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();

    const usr_id = try paths.intern(ROOT, "usr");
    try std.testing.expectEqual(1, @backingInt(usr_id));
    try std.testing.expectEqualDeep("usr", paths.getElementName(usr_id));

    const local_id = try paths.intern(usr_id, "local");
    try std.testing.expectEqual(2, @backingInt(local_id));

    const share_id = try paths.intern(local_id, "share");
    try std.testing.expectEqual(3, @backingInt(share_id));

    const bin_id = try paths.intern(local_id, "bin");
    try std.testing.expectEqual(4, @backingInt(bin_id));

    const another_local_id = try paths.intern(usr_id, "local");
    try std.testing.expectEqual(2, @backingInt(another_local_id));
}
