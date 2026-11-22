const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const HashMapUnmanaged = std.hash_map.HashMapUnmanaged;

const Interned = @import("Interned.zig");
const Pathnames = @import("Pathnames.zig");
const PathIndexer = @import("PathIndexer.zig");
pub const Object = @import("Object.zig");

const HandleInt = u32;
pub const Handle = enum(HandleInt) { _ };
pub const LAST_HANDLE: Handle = @fromBackingInt(std.math.maxInt(HandleInt));

pub const AppendError = Allocator.Error || error{DuplicatePath};

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

            handle: Handle,
            next_handle: []const Handle,
            objects: []const Object,

            pub fn peek(self: *const Iter) ?Object {
                if (self.handle == LAST_HANDLE) return null;
                return self.objects[@backingInt(self.handle)];
            }

            pub fn next(self: *Iter) ?Object {
                if (self.handle == LAST_HANDLE) return null;
                defer self.handle = self.next_handle[@backingInt(self.handle)];
                return self.objects[@backingInt(self.handle)];
            }
        };

        index: HashMapUnmanaged(K, Handle, Context, 80) = .empty,
        next_handle: std.ArrayList(Handle) = .empty,

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.index.deinit(allocator);
            self.next_handle.deinit(allocator);
        }

        pub fn add(self: *Self, allocator: Allocator, key: K) AppendError!void {
            const slot = try self.index.getOrPutContext(allocator, key, .{});
            const head_handle = if (slot.found_existing) slot.value_ptr.* else LAST_HANDLE;
            slot.value_ptr.* = @fromBackingInt(@intCast(self.next_handle.items.len));
            try self.next_handle.append(allocator, head_handle);
        }

        pub fn size(self: *const Self) usize {
            return self.next_handle.items.len;
        }

        fn iterForHandle(self: *const Self, objects: []const Object, handle: Handle) ItemIter {
            return .{
                .handle = handle,
                .next_handle = self.next_handle.items,
                .objects = objects,
            };
        }

        pub fn iterForKey(self: *const Self, objects: []const Object, key: K) ItemIter {
            if (self.index.get(key)) |handle|
                return self.iterForHandle(objects, handle);
            return self.iterForHandle(&.{}, LAST_HANDLE);
        }
    };
}

pub const INodeIndex = MultiIndex(Io.File.INode, IntContext(Io.File.INode));
pub const HashIndex = MultiIndex(u256, HashContext);

const PathIndex = struct {
    const Self = @This();
    pub const empty: Self = .{};

    index: HashMapUnmanaged(Pathnames.Handle, Handle, IntContext(Pathnames.Handle), 80) = .empty,
    used: usize = 0,

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.index.deinit(allocator);
    }

    pub fn add(self: *Self, allocator: Allocator, key: Pathnames.Handle) AppendError!void {
        const slot = try self.index.getOrPutContext(allocator, key, .{});
        if (slot.found_existing)
            return error.DuplicatePath;
        slot.value_ptr.* = @fromBackingInt(@intCast(self.used));
        self.used += 1;
    }

    pub fn size(self: *const Self) usize {
        return self.used;
    }
};

const Manifest = @This();

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
    try self.objects.append(self.allocator, object);
}

fn syncIndex(
    self: *Manifest,
    comptime field: []const u8,
) AppendError!*const @TypeOf(@field(self, field ++ "_index")) {
    const index = &@field(self, field ++ "_index");
    for (self.objects.items[index.size()..self.size()]) |object|
        try index.add(self.allocator, @field(object, field));
    return index;
}

pub fn get(self: *const Manifest, handle: Handle) Object {
    return self.objects.items[@backingInt(handle)];
}

pub fn pathIndex(self: *Manifest) AppendError!*const PathIndex {
    return self.syncIndex("path");
}

pub fn iNodeIndex(self: *Manifest) AppendError!*const INodeIndex {
    return self.syncIndex("inode");
}

pub fn hashIndex(self: *Manifest) AppendError!*const HashIndex {
    return self.syncIndex("hash");
}

pub fn iNodeIter(self: *Manifest, inode: Io.File.INode) AppendError!INodeIndex.ItemIter {
    return (try self.iNodeIndex()).iterForKey(self.objects.items, inode);
}

pub fn hashIter(self: *Manifest, hash: u256) AppendError!HashIndex.ItemIter {
    return (try self.hashIndex()).iterForKey(self.objects.items, hash);
}

pub fn findPathname(self: *Manifest, path: Pathnames.Handle) AppendError!?Object {
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
    var maf: Manifest = .init(std.testing.allocator, &paths);
    defer maf.deinit();

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
    try maf.append(main_obj);

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
    try maf.append(root_obj);

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
    try maf.append(tmp_obj);

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
    try maf.append(mule_obj);

    var nf_iter = try maf.hashIter(0xdeadbeef);
    try std.testing.expectEqual(null, nf_iter.next());
    try std.testing.expectEqual(null, nf_iter.next());

    var main_iter = try maf.hashIter(0x123);
    try std.testing.expectEqualDeep(mule_obj, main_iter.next());
    try std.testing.expectEqualDeep(main_obj, main_iter.next());
    try std.testing.expectEqual(null, main_iter.next());

    var inode_iter = try maf.iNodeIter(3);
    try std.testing.expectEqualDeep(tmp_obj, inode_iter.peek());
    try std.testing.expectEqualDeep(tmp_obj, inode_iter.next());
    try std.testing.expectEqualDeep(root_obj, inode_iter.peek());
    try std.testing.expectEqualDeep(root_obj, inode_iter.next());
    try std.testing.expectEqual(null, inode_iter.peek());
    try std.testing.expectEqual(null, inode_iter.next());

    const tmp_found = try maf.findPathname(tmp_path);
    try std.testing.expectEqualDeep(tmp_obj, tmp_found);
}
