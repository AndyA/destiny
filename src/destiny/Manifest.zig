const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const HashMapUnmanaged = std.hash_map.HashMapUnmanaged;

const Interned = @import("Interned.zig");
const Pathnames = @import("Pathnames.zig");
const PathIndexer = @import("PathIndexer.zig");

pub const LAST_HANDLE = std.math.maxInt(u32);
pub const AppendError = Allocator.Error || error{DuplicatePath};

pub const Object = @import("Object.zig");

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

fn MultiIndex(comptime K: type, comptime Context: type) type {
    return struct {
        const Self = @This();
        pub const empty: Self = .{};

        pub const ItemIter = struct {
            const Iter = @This();

            handle: u32,
            next_handle: []const u32,
            objects: []const Object,

            pub fn peek(self: *Iter) ?Object {
                if (self.handle == LAST_HANDLE) return null;
                return self.objects[self.handle];
            }

            pub fn next(self: *Iter) ?Object {
                if (self.handle == LAST_HANDLE) return null;
                defer self.handle = self.next_handle[self.handle];
                return self.objects[self.handle];
            }
        };

        index: HashMapUnmanaged(K, u32, Context, 80) = .empty,
        next_handle: std.ArrayList(u32) = .empty,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.index.deinit(gpa);
            self.next_handle.deinit(gpa);
        }

        pub fn add(self: *Self, gpa: Allocator, key: K) AppendError!void {
            const slot = try self.index.getOrPutContext(gpa, key, .{});
            const link = if (slot.found_existing) slot.value_ptr.* else LAST_HANDLE;
            slot.value_ptr.* = @intCast(self.next_handle.items.len);
            try self.next_handle.append(gpa, link);
        }

        pub fn size(self: *const Self) usize {
            return self.next_handle.items.len;
        }

        pub fn iterForHandle(self: *const Self, objects: []const Object, handle: u32) ItemIter {
            return .{
                .handle = handle,
                .next_handle = self.next_handle.items,
                .objects = objects,
            };
        }

        pub fn iterForKey(self: *const Self, objects: []const Object, key: K) ItemIter {
            if (self.index.get(key)) |handle|
                return self.iterForHandle(objects, handle);
            return self.iterForHandle(objects, LAST_HANDLE);
        }
    };
}

const PathIndex = struct {
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

const Manifest = @This();

pub const INodeIndex = MultiIndex(Io.File.INode, IntContext(Io.File.INode));
pub const HashIndex = MultiIndex(u256, HashContext);

allocator: Allocator,
pathnames: *Pathnames,

objects: std.ArrayList(Object) = .empty,

path_index: PathIndex = .empty,
inode_index: INodeIndex = .empty,
hash_index: HashIndex = .empty,

pub fn init(allocator: Allocator, pathnames: *Pathnames) Manifest {
    return .{ .allocator = allocator, .pathnames = pathnames };
}

pub fn deinit(self: *Manifest) void {
    self.objects.deinit(self.allocator);

    self.path_index.deinit(self.allocator);
    self.inode_index.deinit(self.allocator);
    self.hash_index.deinit(self.allocator);
}

pub fn size(self: *const Manifest) usize {
    return self.objects.items.len;
}

pub fn append(self: *Manifest, object: Object) AppendError!void {
    const handle: u32 = @intCast(self.objects.items.len);
    assert(handle != LAST_HANDLE);
    try self.objects.append(self.allocator, object);
}

fn updateIndex(
    self: *Manifest,
    comptime index_field: []const u8,
    comptime object_field: []const u8,
) AppendError!*const @TypeOf(@field(self, index_field)) {
    const index = &@field(self, index_field);
    for (self.objects.items[index.size()..self.size()]) |object|
        try index.add(self.allocator, @field(object, object_field));
    return index;
}

pub fn get(self: *const Manifest, handle: u32) Object {
    return self.objects.items[handle];
}

pub fn pathIndex(self: *Manifest) AppendError!*const PathIndex {
    return self.updateIndex("path_index", "path");
}

pub fn iNodeIndex(self: *Manifest) AppendError!*const INodeIndex {
    return self.updateIndex("inode_index", "inode");
}

pub fn hashIndex(self: *Manifest) AppendError!*const HashIndex {
    return self.updateIndex("hash_index", "hash");
}

pub fn iNodeIter(self: *Manifest, inode: Io.File.INode) AppendError!INodeIndex.ItemIter {
    return (try self.iNodeIndex()).iterForKey(self.objects.items, inode);
}

pub fn hashIter(self: *Manifest, hash: u256) AppendError!HashIndex.ItemIter {
    return (try self.hashIndex()).iterForKey(self.objects.items, hash);
}

pub fn findPathname(self: *Manifest, path: u32) AppendError!?Object {
    if ((try self.pathIndex()).index.get(path)) |handle|
        return self.get(handle);
    return null;
}

pub fn findINode(self: *Manifest, inode: Io.File.INode) AppendError!?Object {
    if ((try self.iNodeIndex()).index.get(inode)) |handle|
        return self.get(handle);
    return null;
}

pub fn findHash(self: *Manifest, hash: u256) AppendError!?Object {
    if ((try self.hashIndex()).index.get(hash)) |handle|
        return self.get(handle);
    return null;
}

test Manifest {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();
    var indexer: PathIndexer = .init(std.testing.allocator, &paths);
    defer indexer.deinit();
    var mf: Manifest = .init(std.testing.allocator, &paths);
    defer mf.deinit();

    const main_path = try indexer.index("src/main.zig");
    const main_obj: Object = .{
        .path = main_path,
        .inode = 1,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(0),
        .permissions = @fromBackingInt(0),
        .hash = 0x123,
        .size = 123,
    };
    try mf.append(main_obj);

    const root_path = try indexer.index("src/root.zig");
    const root_obj: Object = .{
        .path = root_path,
        .inode = 3,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(0),
        .permissions = @fromBackingInt(0),
        .hash = 0x321,
        .size = 321,
    };
    try mf.append(root_obj);

    const tmp_path = try indexer.index("tmp/root.zig");
    const tmp_obj: Object = .{
        .path = tmp_path,
        .inode = 3,
        .kind = .file,
        .mtime = Io.Timestamp.fromNanoseconds(0),
        .permissions = @fromBackingInt(0),
        .hash = 0x321,
        .size = 321,
    };
    try mf.append(tmp_obj);

    const mule_path = try indexer.index("src/mule.zig");
    const mule_obj: Object = .{
        .path = mule_path,
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
    try std.testing.expectEqualDeep(tmp_obj, inode_iter.peek());
    try std.testing.expectEqualDeep(tmp_obj, inode_iter.next());
    try std.testing.expectEqualDeep(root_obj, inode_iter.peek());
    try std.testing.expectEqualDeep(root_obj, inode_iter.next());
    try std.testing.expectEqual(null, inode_iter.peek());
    try std.testing.expectEqual(null, inode_iter.next());

    const tmp_found = try mf.findPathname(tmp_path);
    try std.testing.expectEqualDeep(tmp_obj, tmp_found);
}
