const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const HashMapUnmanaged = std.hash_map.HashMapUnmanaged;

const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");
const PathIndexer = @import("destiny/PathIndexer.zig");

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

const LINK_LAST = std.math.maxInt(u32);
const AppendError = Allocator.Error || error{ DuplicateINode, DuplicatePath };

fn MultiIndex(comptime K: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        pub const empty: Self = .{};

        pub const ItemIter = struct {
            const Iter = @This();

            handle: u32,
            next_link: []const u32,
            objects: []const Object,

            pub fn peek(self: *Iter) ?Object {
                if (self.handle == LINK_LAST) return null;
                return self.objects[self.handle];
            }

            pub fn next(self: *Iter) ?Object {
                if (self.handle == LINK_LAST) return null;
                defer self.handle = self.next_link[self.handle];
                return self.objects[self.handle];
            }
        };

        index: HashMapUnmanaged(K, u32, Context, 80) = .empty,
        next_link: std.ArrayList(u32) = .empty,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.index.deinit(gpa);
            self.next_link.deinit(gpa);
        }

        pub fn add(self: *Self, gpa: Allocator, key: K) AppendError!void {
            const slot = try self.index.getOrPutContext(gpa, key, .{});
            const link = if (slot.found_existing) slot.value_ptr.* else LINK_LAST;
            slot.value_ptr.* = @intCast(self.next_link.items.len);
            try self.next_link.append(gpa, link);
        }

        pub fn size(self: *const Self) usize {
            return self.next_link.items.len;
        }

        pub fn iterForHandle(self: *const Self, objects: []const Object, handle: u32) ItemIter {
            return .{
                .handle = handle,
                .next_link = self.next_link.items,
                .objects = objects,
            };
        }

        pub fn iterForKey(self: *const Self, objects: []const Object, key: K) ItemIter {
            if (self.index.get(key)) |handle|
                return self.iterForHandle(objects, handle);
            return self.iterForHandle(objects, LINK_LAST);
        }
    };
}

pub const PathIndex = struct {
    const Self = @This();
    pub const empty: Self = .{};

    index: HashMapUnmanaged(u32, u32, IntContext(u32), 80) = .empty,
    used: usize = 0,

    pub fn deinit(self: *Self, gpa: Allocator) void {
        self.index.deinit(gpa);
    }

    pub fn add(self: *Self, gpa: Allocator, key: u32) AppendError!void {
        const slot = try self.index.getOrPutContext(gpa, key, .{});
        if (slot.found_existing)
            return error.DuplicatePath;
        slot.value_ptr.* = @intCast(self.used);
        self.used += 1;
    }

    pub fn size(self: *const Self) usize {
        return self.used;
    }
};

pub const Manifest = struct {
    const Self = @This();

    pub const INodeIndex = MultiIndex(Io.File.INode, IntContext(Io.File.INode));
    pub const HashIndex = MultiIndex(u256, HashContext);

    allocator: Allocator,
    pathnames: *Pathnames,

    objects: std.ArrayList(Object) = .empty,

    path_index: PathIndex = .empty,
    inode_index: INodeIndex = .empty,
    hash_index: HashIndex = .empty,

    pub fn init(allocator: Allocator, pathnames: *Pathnames) Self {
        return .{ .allocator = allocator, .pathnames = pathnames };
    }

    pub fn deinit(self: *Self) void {
        self.objects.deinit(self.allocator);

        self.path_index.deinit(self.allocator);
        self.inode_index.deinit(self.allocator);
        self.hash_index.deinit(self.allocator);
    }

    pub fn append(self: *Self, object: Object) AppendError!void {
        const handle: u32 = @intCast(self.objects.items.len);
        assert(handle != LINK_LAST);
        try self.objects.append(self.allocator, object);
    }

    fn updateIndex(
        self: *Self,
        comptime index_field: []const u8,
        comptime object_field: []const u8,
    ) AppendError!*const @TypeOf(@field(self, index_field)) {
        const index = &@field(self, index_field);
        const start = index.size();
        const end = self.objects.items.len;

        for (self.objects.items[start..end]) |object| {
            try index.add(self.allocator, @field(object, object_field));
        }

        return index;
    }

    pub fn pathIndex(self: *Self) AppendError!*const PathIndex {
        return self.updateIndex("path_index", "path");
    }

    pub fn iNodeIndex(self: *Self) AppendError!*const INodeIndex {
        return self.updateIndex("inode_index", "inode");
    }

    pub fn iNodeIter(self: *Self, inode: Io.File.INode) AppendError!INodeIndex.ItemIter {
        return (try self.iNodeIndex()).iterForKey(self.objects.items, inode);
    }

    pub fn hashIndex(self: *Self) AppendError!*const HashIndex {
        return self.updateIndex("hash_index", "hash");
    }

    pub fn hashIter(self: *Self, hash: u256) AppendError!HashIndex.ItemIter {
        return (try self.hashIndex()).iterForKey(self.objects.items, hash);
    }
};

test Manifest {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();
    var indexer: PathIndexer = .init(std.testing.allocator, &paths);
    defer indexer.deinit();
    var mf: Manifest = .init(std.testing.allocator, &paths);
    defer mf.deinit();

    const main_id = try indexer.index("src/main.zig");
    const main_obj: Object = .{
        .path = main_id,
        .inode = 1,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(0),
        .permissions = @fromBackingInt(0),
        .hash = 0x123,
        .size = 123,
    };
    try mf.append(main_obj);

    const root_id = try indexer.index("src/root.zig");
    const root_obj: Object = .{
        .path = root_id,
        .inode = 3,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(0),
        .permissions = @fromBackingInt(0),
        .hash = 0x321,
        .size = 321,
    };
    try mf.append(root_obj);

    const tmp_id = try indexer.index("tmp/root.zig");
    const tmp_obj: Object = .{
        .path = tmp_id,
        .inode = 3,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(0),
        .permissions = @fromBackingInt(0),
        .hash = 0x321,
        .size = 321,
    };
    try mf.append(tmp_obj);

    const mule_id = try indexer.index("src/mule.zig");
    const mule_obj: Object = .{
        .path = mule_id,
        .inode = 2,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(3_000_000),
        .permissions = @fromBackingInt(0o777),
        .hash = 0x123,
        .size = 123,
    };
    try mf.append(mule_obj);

    var nf_iter = try mf.hashIter(0xdeadbeef);
    try std.testing.expectEqual(null, nf_iter.next());
    try std.testing.expectEqual(null, nf_iter.next());

    var ott_iter = try mf.hashIter(0x123);
    try std.testing.expectEqualDeep(mule_obj, ott_iter.next());
    try std.testing.expectEqualDeep(main_obj, ott_iter.next());
    try std.testing.expectEqual(null, ott_iter.next());

    var inode_iter = try mf.iNodeIter(3);
    try std.testing.expectEqualDeep(tmp_obj, inode_iter.next());
    try std.testing.expectEqualDeep(root_obj, inode_iter.next());
    try std.testing.expectEqual(null, inode_iter.next());
}

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
