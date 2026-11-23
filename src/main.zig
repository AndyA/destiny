const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");
const PathWriter = @import("destiny/PathWriter.zig");
const Manifest = @import("destiny/Manifest.zig");
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

    allocator: Allocator,
    manifest: Manifest,
    search: std.ArrayList(Manifest) = .empty,

    pub fn deinit(self: *Self) void {
        self.manifest.deinit();
        for (&self.search.items) |*item|
            item.deinit();
        self.search.deinit(self.allocator);
    }
};

pub fn main(init: std.process.Init) !void {
    var int: Interned = try .init(init.gpa);
    defer int.deinit();
    var paths: Pathnames = try .init(init.gpa, &int);
    defer paths.deinit();
    var pw: PathWriter = .init(init.gpa, &paths);
    defer pw.deinit();

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

    const openOptions: Io.Dir.OpenOptions = .{ .follow_symlinks = false, .iterate = true };
    const dir = try Io.Dir.openDir(Io.Dir.cwd(), init.io, ".", openOptions);

    if (false) {
        const fh = try dir.openFile(init.io, "tmp/video.mov", .{ .mode = .read_only });
        defer fh.close(init.io);

        const hash = try sha256File(init.io, fh);
        print("hash: {x}\n", .{hash});
    }

    var scanner: fi.FileIterator(Context, openOptions) = try .init(
        init.gpa,
        init.io,
        &paths,
        dir,
        .{ .sorted = true },
    );
    defer scanner.deinit();

    while (try scanner.next()) |item| {
        print("{f} ({s})\n", .{ pw.fmt(item.entry.path), @tagName(item.entry.kind) });
    }

    for (1..int.index.items.len) |h| {
        print("{d:>3}: \"{s}\"\n", .{ h, int.get(@fromBackingInt(@as(u32, @intCast(h)))) });
    }
}
