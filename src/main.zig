const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");
const PathWriter = @import("destiny/PathWriter.zig");
const Manifest = @import("destiny/Manifest.zig");
const Object = @import("destiny/Object.zig");
const fi = @import("destiny/file_iterator.zig");
const sha256File = @import("destiny/tools.zig").sha256File;

test {
    _ = @import("destiny/Interned.zig");
    _ = @import("destiny/Pathnames.zig");
    _ = @import("destiny/PathIndexer.zig");
    _ = @import("destiny/PathWriter.zig");
    _ = @import("destiny/Manifest.zig");
    _ = @import("destiny/file_iterator.zig");
}

pub const Scan = struct {
    const Self = @This();

    pub const openOptions: Io.Dir.OpenOptions = .{
        .follow_symlinks = false,
        .iterate = true,
    };

    pub const Error = Manifest.AppendError ||
        Io.File.StatError ||
        Io.File.OpenError ||
        Io.File.ReadStreamingError;

    allocator: Allocator,
    io: Io,
    pathnames: *Pathnames,

    manifest: Manifest,
    path_writer: PathWriter,
    search: std.ArrayList(Manifest) = .empty,

    pub fn init(allocator: Allocator, io: Io, pathnames: *Pathnames) Self {
        return .{
            .allocator = allocator,
            .io = io,
            .pathnames = pathnames,
            .manifest = .init(allocator, pathnames),
            .path_writer = .init(allocator, pathnames),
        };
    }

    pub fn deinitShallow(self: *Self) void {
        self.manifest.deinit();
        self.search.deinit(self.allocator);
        self.path_writer.deinit();
    }

    pub fn deinit(self: *Self) void {
        for (self.search.items) |*item|
            item.deinit();
        self.deinitShallow();
    }

    fn fmtPath(self: *Self, path: Pathnames.Handle) PathWriter.Fmt {
        return self.path_writer.fmt(path);
    }

    fn objectMatches(object: Object, stat: Io.File.Stat) bool {
        return object.size == stat.size and
            object.permissions == stat.permissions and
            object.mtime.nanoseconds == stat.mtime.nanoseconds;
    }

    fn matchInManifest(manifest: *Manifest, path: Pathnames.Handle, stat: Io.File.Stat) Error!?Object {
        if (try manifest.findPathname(path)) |found| {
            if (objectMatches(found, stat))
                return found;
        }
        if (try manifest.findINode(stat.inode)) |found| {
            if (objectMatches(found, stat))
                return found;
        }
        return null;
    }

    fn matchObject(self: *Self, path: Pathnames.Handle, stat: Io.File.Stat) Error!?Object {
        for (self.search.items) |*manifest| {
            if (try matchInManifest(manifest, path, stat)) |found|
                return found;
        }
        return null;
    }

    fn createObject(self: *Self, item: fi.FileIteratorItem) Error!Object {
        if (try self.manifest.findINode(item.entry.inode)) |found| {
            var object = found;
            object.path = item.entry.path;
            return object;
        }

        const name = self.pathnames.int.get(item.entry.name);
        const file = try item.dir.openFile(self.io, name, .{ .mode = .read_only });
        defer file.close(self.io);

        const stat = try file.stat(self.io);

        const hash = blk: {
            if (try self.matchObject(item.entry.path, stat)) |found|
                break :blk found.hash;

            const sha256 = try sha256File(self.io, file);
            print("  {x:0>64} {f}\n", .{ sha256, self.fmtPath(item.entry.path) });

            break :blk sha256;
        };

        return .{
            .path = item.entry.path,
            .inode = item.entry.inode,
            .size = stat.size,
            .permissions = stat.permissions,
            .kind = item.entry.kind,
            .mtime = stat.mtime,
            .hash = hash,
        };
    }

    pub fn scan(self: *Self, dir: Io.Dir) Error!void {
        const Context = struct {
            fn isManifest(name: []const u8) bool {
                return std.mem.startsWith(u8, name, "MANIFEST.") and
                    std.mem.endsWith(u8, name, ".json");
            }

            pub fn shouldInclude(_: @This(), _: fi.FileIteratorItem, name: []const u8) bool {
                if (name.len > 0 and name[0] == '.')
                    return false;
                if (isManifest(name))
                    return false;
                return true;
            }
        };

        var scanner: fi.FileIterator(Context, Scan.openOptions) = try .init(
            self.allocator,
            self.io,
            self.pathnames,
            dir,
            .{ .sorted = true },
        );
        defer scanner.deinit();

        while (try scanner.next()) |item| {
            switch (item.entry.kind) {
                .file => {
                    const obj = try self.createObject(item);
                    try self.manifest.append(obj);
                },
                .directory => {
                    print("Scanning {f}\n", .{self.fmtPath(item.entry.path)});
                },
                else => |kind| {
                    print("  Skipping {s} {f}\n", .{ @tagName(kind), self.fmtPath(item.entry.path) });
                },
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var int: Interned = try .init(init.gpa);
    defer int.deinit();
    var paths: Pathnames = try .init(init.gpa, &int);
    defer paths.deinit();
    var pw: PathWriter = .init(init.gpa, &paths);
    defer pw.deinit();

    const dir = try Io.Dir.openDir(Io.Dir.cwd(), init.io, ".", Scan.openOptions);

    var scan: Scan = .init(init.gpa, init.io, &paths);
    defer scan.deinit();
    try scan.scan(dir);

    if (false) {
        const fh = try dir.openFile(init.io, "tmp/video.mov", .{ .mode = .read_only });
        defer fh.close(init.io);

        const hash = try sha256File(init.io, fh);
        print("hash: {x}\n", .{hash});
    }

    if (false) {
        for (1..int.index.items.len) |h| {
            print("{d:>3}: \"{s}\"\n", .{ h, int.get(@fromBackingInt(@as(u32, @intCast(h)))) });
        }
    }
}
