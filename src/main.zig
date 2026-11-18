const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Pathnames = @import("destiny/Pathnames.zig");

test {
    _ = @import("destiny/Interned.zig");
    _ = @import("destiny/Pathnames.zig");
    _ = @import("destiny/PathIndexer.zig");
    _ = @import("destiny/PathWriter.zig");
}

pub const Object = struct {
    path: u32,
    inode: Io.File.INode,
    size: u64,
    permissions: Io.File.Permissions,
    kind: Io.File.Kind,
    mtime: Io.Timestamp,
    hash: u256,
};

fn IntContext(comptime T: type) type {
    return struct {
        pub fn hash(_: @This(), value: T) u64 {
            var hasher: std.hash.Wyhash = .init(0);
            std.hash.autoHash(&hasher, value);
            return hasher.final();
        }

        pub fn eql(_: @This(), a: T, b: T) bool {
            return a == b;
        }
    };
}

const HashContext = struct {
    pub fn hash(_: @This(), value: u256) u64 {
        return @intCast(value & std.math.maxInt(u64));
    }

    pub fn eql(_: @This(), a: u256, b: u256) bool {
        return a == b;
    }
};

pub const Manifest = struct {
    const Self = @This();

    const AppendError = Allocator.Error || error{ DuplicateINode, DuplicatePath };
    const HASH_LAST = std.math.maxInt(u32);

    allocator: Allocator,
    pathnames: *Pathnames,

    objects: std.ArrayList(Object) = .empty,
    hash_next: std.ArrayList(u32) = .empty,

    path_index: std.hash_map.HashMapUnmanaged(
        u32,
        u32,
        IntContext(u32),
        80,
    ) = .empty,

    inode_index: std.hash_map.HashMapUnmanaged(
        Io.File.INode,
        u32,
        IntContext(Io.File.INode),
        80,
    ) = .empty,

    hash_index: std.hash_map.HashMapUnmanaged(
        u256,
        u32,
        HashContext,
        80,
    ) = .empty,

    pub fn init(allocator: Allocator, pathnames: *Pathnames) Self {
        return .{ .allocator = allocator, .pathnames = pathnames };
    }

    pub fn deinit(self: *Self) void {
        self.objects.deinit(self.allocator);
        self.hash_next.deinit(self.allocator);
        self.path_index.deinit(self.allocator);
        self.inode_index.deinit(self.allocator);
        self.hash_index.deinit(self.allocator);
    }

    pub fn append(self: *Self, object: Object) AppendError!void {
        const handle = self.objects.items.len;
        assert(self.hash_next.items.len == handle);
        try self.objects.append(self.allocator, object);

        // Update the hash chain
        {
            const slot = try self.hash_index.getOrPutContext(
                self.allocator,
                object.hash,
                .{},
            );
            const hash_link = if (slot.found_existing) slot.value_ptr.* else HASH_LAST;
            slot.value_ptr.* = handle;
            try self.hash_next.append(self.allocator, hash_link);
        }

        // Update the inode index
        {
            const slot = try self.inode_index.getOrPutContext(
                self.allocator,
                object.inode,
                .{},
            );
            if (slot.found_existing)
                return error.DuplicateINode;
            slot.value_ptr.* = handle;
        }

        // Update the path index
        {
            const slot = try self.path_index.getOrPutContext(
                self.allocator,
                object.path,
                .{},
            );
            if (slot.found_existing)
                return error.DuplicatePath;
            slot.value_ptr.* = handle;
        }
    }
};

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
