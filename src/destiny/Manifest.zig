const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const HashMapUnmanaged = std.hash_map.HashMapUnmanaged;

const Interned = @import("Interned.zig");
const Pathnames = @import("Pathnames.zig");
const PathIndexer = @import("PathIndexer.zig");
const PathWriter = @import("PathWriter.zig");
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
            next_handle: *std.ArrayList(Handle),
            objects: *std.ArrayList(Object),

            pub fn peek(self: *const Iter) ?Object {
                if (self.handle == LAST_HANDLE) return null;
                return self.objects.items[@backingInt(self.handle)];
            }

            pub fn next(self: *Iter) ?Object {
                if (self.handle == LAST_HANDLE) return null;
                defer self.handle = self.next_handle.items[@backingInt(self.handle)];
                return self.objects.items[@backingInt(self.handle)];
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

        fn iterForHandle(self: *Self, objects: *std.ArrayList(Object), handle: Handle) ItemIter {
            return .{ .handle = handle, .next_handle = &self.next_handle, .objects = objects };
        }

        pub fn iterForKey(self: *Self, objects: *std.ArrayList(Object), key: K) ItemIter {
            if (self.index.get(key)) |handle|
                return self.iterForHandle(objects, handle);
            return self.iterForHandle(objects, LAST_HANDLE);
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
) AppendError!*@FieldType(Manifest, field ++ "_index") {
    const index = &@field(self, field ++ "_index");
    for (self.objects.items[index.size()..self.size()]) |object|
        try index.add(self.allocator, @field(object, field));
    return index;
}

pub fn get(self: *const Manifest, handle: Handle) Object {
    return self.objects.items[@backingInt(handle)];
}

pub fn pathIndex(self: *Manifest) AppendError!*PathIndex {
    return self.syncIndex("path");
}

pub fn iNodeIndex(self: *Manifest) AppendError!*INodeIndex {
    return self.syncIndex("inode");
}

pub fn hashIndex(self: *Manifest) AppendError!*HashIndex {
    return self.syncIndex("hash");
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

pub fn iNodeIter(self: *Manifest, inode: Io.File.INode) AppendError!INodeIndex.ItemIter {
    return (try self.iNodeIndex()).iterForKey(&self.objects, inode);
}

pub fn hashIter(self: *Manifest, hash: u256) AppendError!HashIndex.ItemIter {
    return (try self.hashIndex()).iterForKey(&self.objects, hash);
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

pub const WriteJsonError = PathWriter.Error || Io.File.Writer.Error;

fn beginObjectField(
    stringify: *std.json.Stringify,
    writer: *Io.Writer,
    name: []const u8,
) WriteJsonError!void {
    try stringify.objectField(name);
    try stringify.beginWriteRaw();
    try writer.writeByte('"');
}

fn endObjectField(stringify: *std.json.Stringify, writer: *Io.Writer) WriteJsonError!void {
    try writer.writeByte('"');
    stringify.endWriteRaw();
}

fn printObjectField(
    stringify: *std.json.Stringify,
    writer: *Io.Writer,
    name: []const u8,
    comptime fmt: []const u8,
    args: anytype,
) WriteJsonError!void {
    try beginObjectField(stringify, writer, name);
    try writer.print(fmt, args);
    try endObjectField(stringify, writer);
}

pub fn writeJson(self: Manifest, writer: *Io.Writer) WriteJsonError!void {
    var pw: PathWriter = .init(self.allocator, self.pathnames);
    defer pw.deinit();

    for (self.objects.items) |object| {
        var stringify: std.json.Stringify = .{ .writer = writer };
        try stringify.beginObject();
        {
            try beginObjectField(&stringify, writer, "path");
            try pw.writePathJson(writer, object.path);
            try endObjectField(&stringify, writer);
        }
        try printObjectField(&stringify, writer, "inode", "{d}", .{object.inode});
        try printObjectField(&stringify, writer, "size", "{d}", .{object.size});
        try printObjectField(&stringify, writer, "perms", "{o}", .{
            @backingInt(object.permissions),
        });
        try printObjectField(&stringify, writer, "mtime", "{d}", .{
            object.mtime.toMicroseconds(),
        });
        try printObjectField(&stringify, writer, "hash", "{x:0>64}", .{object.hash});
        try stringify.endObject();
        try writer.writeByte('\n');
    }
}

pub const ReadJsonError = std.fmt.ParseIntError ||
    std.json.Scanner.Reader.NextError ||
    std.json.Scanner.Reader.AllocError ||
    AppendError ||
    error{SyntaxError};

const ParserContext = struct {
    indexer: *PathIndexer,
};

fn pathParser(comptime name: []const u8) type {
    return struct {
        pub fn parseField(ctx: ParserContext, object: *Object, field: []const u8) ReadJsonError!void {
            @field(object, name) = try ctx.indexer.index(field);
        }
    };
}

fn intParser(comptime name: []const u8, comptime base: comptime_int) type {
    const FT = @FieldType(Object, name);
    const info = @typeInfo(FT);
    return switch (info) {
        .int => struct {
            pub fn parseField(_: ParserContext, object: *Object, field: []const u8) ReadJsonError!void {
                @field(object, name) = try std.fmt.parseInt(FT, field, base);
            }
        },
        .@"enum" => |E| struct {
            pub fn parseField(_: ParserContext, object: *Object, field: []const u8) ReadJsonError!void {
                @field(object, name) = @fromBackingInt(
                    try std.fmt.parseInt(E.tag_type, field, base),
                );
            }
        },
        else => @compileError("intParser can't parse a " ++ @tagName(info)),
    };
}

fn timeParser(comptime name: []const u8) type {
    return struct {
        pub fn parseField(_: ParserContext, object: *Object, field: []const u8) ReadJsonError!void {
            const microseconds = try std.fmt.parseInt(i96, field, 10);
            @field(object, name) = .fromNanoseconds(microseconds * std.time.ns_per_us);
        }
    };
}

const parsers = .{
    .path = pathParser("path"),
    .inode = intParser("inode", 10),
    .size = intParser("size", 10),
    .perms = intParser("permissions", 8),
    .mtime = timeParser("mtime"),
    .hash = intParser("hash", 16),
};

const FieldMask = blk: {
    const info = @typeInfo(@TypeOf(parsers)).@"struct";
    break :blk @Int(.unsigned, info.field_names.len);
};

fn freeToken(gpa: Allocator, tok: std.json.Token) void {
    switch (tok) {
        .allocated_number, .allocated_string => |s| gpa.free(s),
        else => {},
    }
}
pub fn readJsonBelow(self: *Manifest, io_reader: *Io.Reader, root: Pathnames.Handle) ReadJsonError!void {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var indexer: PathIndexer = .initBelow(gpa, self.pathnames, root);
    defer indexer.deinit();
    var reader: std.json.Scanner.Reader = .init(gpa, io_reader);
    defer reader.deinit();
    const ctx: ParserContext = .{ .indexer = &indexer };
    const parsers_info = @typeInfo(@TypeOf(parsers)).@"struct";

    maf: while (true) {
        var object: Object = undefined;
        object.kind = Io.File.Kind.file;

        // Restart the scanner for each object
        reader.scanner.state = .value;

        const tok = reader.next() catch |err| switch (err) {
            error.UnexpectedEndOfInput => break :maf,
            else => return err,
        };

        if (tok != .object_begin)
            return error.SyntaxError;

        var seen: FieldMask = 0;

        obj: while (true) {
            const key_token = try reader.nextAlloc(gpa, .alloc_if_needed);
            defer freeToken(gpa, key_token);
            switch (key_token) {
                .object_end => break :obj,
                .string, .allocated_string => |field| {
                    inline for (parsers_info.field_names, 0..) |name, i| {
                        if (std.mem.eql(u8, field, name)) {
                            seen |= 1 << @intCast(i);
                            const Parser = @field(parsers, name);
                            const value_token = try reader.nextAlloc(gpa, .alloc_if_needed);
                            defer freeToken(gpa, value_token);
                            try Parser.parseField(ctx, &object, switch (value_token) {
                                .string, .allocated_string => |str| str,
                                else => return error.SyntaxError,
                            });
                            continue :obj;
                        }
                    }
                    std.log.err("Unknown field: {s}", .{field});
                    return error.SyntaxError;
                },
                else => return error.SyntaxError,
            }
        }

        if (seen != std.math.maxInt(FieldMask)) {
            std.log.err("Missing fields:", .{});
            inline for (parsers_info.field_names, 0..) |name, i| {
                if ((seen & (1 << @intCast(i))) == 0)
                    std.log.err("  {s}", .{name});
            }

            return error.SyntaxError;
        }

        try self.append(object);
    }
}

pub fn readJson(self: *Manifest, io_reader: *Io.Reader) ReadJsonError!void {
    try self.readJsonBelow(io_reader, Pathnames.ROOT);
}

test readJson {
    const MANIFEST =
        \\{
        \\  "path": "README.md",
        \\  "inode": "402466422",
        \\  "size": "2369",
        \\  "perms": "100644",
        \\  "mtime": "1795524519002739982",
        \\  "hash": "c826f07ee0aafb8838e1568559cc884b06cecc87a1077c5fc7a2023797d491b6"
        \\}
        \\{
        \\  "hash": "6cc053fb6616df0da2a4f43b3b5ef8dc4a075d37c7d1b4b77f7b056a4bfa8cec",
        \\  "inode": "401462719",
        \\  "size": "1019",
        \\  "perms": "100644",
        \\  "mtime": "1795015600704883478",
        \\  "path": "build.zig"
        \\}
        \\{
        \\  "path": "build.zig.zon",
        \\  "inode": "401462720",
        \\  "size": "522",
        \\  "perms": "100644",
        \\  "mtime": "1795015386347382301",
        \\  "hash": "aa9bc9cc6a350224b1206040d5c361ca38c53ff80527b7c457ba2fe48283afaf"
        \\}
    ;

    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();
    var maf: Manifest = .init(std.testing.allocator, &paths);
    defer maf.deinit();

    var reader: Io.Reader = .fixed(MANIFEST);
    try maf.readJson(&reader);
}

pub const SaveError = Io.File.OpenError ||
    Io.File.Writer.Error ||
    WriteJsonError ||
    Io.Dir.RenameError;

pub fn save(self: Manifest, io: Io, dir: Io.Dir, name: []const u8) SaveError!void {
    assert(!std.fs.path.isAbsolute(name));
    const tmp_name = "tmp.MANIFEST.json";
    {
        const m_file = try dir.createFile(io, tmp_name, .{});
        defer m_file.close(io);
        var buf: [128 * 1024]u8 = undefined;
        var writer = m_file.writer(io, &buf);
        try self.writeJson(&writer.interface);
        try writer.flush();
    }
    try dir.rename(tmp_name, dir, name, io);
}

pub const LoadError = Io.File.OpenError ||
    Io.File.Reader.Error ||
    ReadJsonError;

pub fn loadBelow(
    self: *Manifest,
    io: Io,
    dir: Io.Dir,
    name: []const u8,
    root: Pathnames.Handle,
) LoadError!void {
    const m_file = blk: {
        if (std.fs.path.isAbsolute(name))
            break :blk try Io.Dir.openFileAbsolute(io, name, .{ .mode = .read_only });
        break :blk try dir.openFile(io, name, .{ .mode = .read_only });
    };
    defer m_file.close(io);
    var buf: [128 * 1024]u8 = undefined;
    var reader = m_file.reader(io, &buf);
    self.readJsonBelow(&reader.interface, root) catch |err| {
        std.log.err("Error in {s} at object {d}", .{ name, self.objects.items.len + 1 });
        return err;
    };
}

pub fn load(self: *Manifest, io: Io, dir: Io.Dir, name: []const u8) LoadError!void {
    try self.loadBelow(self, io, dir, name, Pathnames.ROOT);
}
