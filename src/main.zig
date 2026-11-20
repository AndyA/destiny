const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");
const PathWriter = @import("destiny/PathWriter.zig");

test {
    _ = @import("destiny/Interned.zig");
    _ = @import("destiny/Pathnames.zig");
    _ = @import("destiny/PathIndexer.zig");
    _ = @import("destiny/PathWriter.zig");
    _ = @import("destiny/Manifest.zig");
}
const FileIteratorItem = struct {
    path: Pathnames.Handle,
    dir: Io.Dir,
    entry: Io.Dir.Entry,
};

pub fn FileIterator(comptime Context: type) type {
    return struct {
        const Self = @This();

        const Error = Allocator.Error || Io.Dir.Reader.Error || Io.Dir.OpenError;

        const Frame = struct {
            path: Pathnames.Handle,
            dir: Io.Dir,
            iter: Io.Dir.Iterator,
        };

        allocator: Allocator,
        io: Io,
        pathnames: *Pathnames,
        ctx: Context,
        stack: std.ArrayList(Frame) = .empty,

        pub fn init(
            allocator: Allocator,
            io: Io,
            pathnames: *Pathnames,
            ctx: Context,
            path: Pathnames.Handle,
            dir: Io.Dir,
        ) Allocator.Error!Self {
            var self: Self = .{
                .allocator = allocator,
                .io = io,
                .pathnames = pathnames,
                .ctx = ctx,
            };
            try self.push(path, dir);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit(self.allocator);
        }

        fn push(self: *Self, path: Pathnames.Handle, dir: Io.Dir) Allocator.Error!void {
            try self.stack.append(self.allocator, .{
                .path = path,
                .dir = dir,
                .iter = dir.iterate(),
            });
        }

        fn pop(self: *Self) void {
            assert(self.stack.items.len != 0);
            defer self.stack.items.len -= 1;
            const frame = self.stack.items[self.stack.items.len - 1];
            frame.dir.close(self.io);
        }

        fn topOfStack(self: *const Self) ?*Frame {
            if (self.stack.items.len == 0) return null;
            return &self.stack.items[self.stack.items.len - 1];
        }

        fn descend(self: *Self, tos: *const Frame, item: FileIteratorItem) Error!void {
            const sub_dir = try tos.dir.openDir(self.io, item.entry.name, .{
                .access_sub_paths = true,
                .iterate = true,
                .follow_symlinks = false,
            });
            try self.push(item.path, sub_dir);
        }

        fn shouldInclude(self: *const Self, item: FileIteratorItem) bool {
            if (@typeInfo(Context) == .@"struct" and @hasDecl(Context, "shouldInclude")) {
                return self.ctx.shouldInclude(item);
            }
            return true;
        }

        pub fn next(self: *Self) Error!?FileIteratorItem {
            while (true) {
                if (self.topOfStack()) |tos| {
                    if (try tos.iter.next(self.io)) |entry| {
                        const path = try self.pathnames.intern(tos.path, entry.name);
                        const item: FileIteratorItem = .{
                            .path = path,
                            .dir = tos.dir,
                            .entry = entry,
                        };
                        if (!self.shouldInclude(item))
                            continue;
                        if (entry.kind == .directory)
                            try self.descend(tos, item);
                        return item;
                    }
                    self.pop();
                } else {
                    return null;
                }
            }
        }
    };
}

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

        pub fn shouldInclude(_: @This(), item: FileIteratorItem) bool {
            const name = item.entry.name;
            if (name.len > 0 and name[0] == '.')
                return false;
            if (isManifest(name))
                return false;
            return true;
        }
    };

    const dir = try Io.Dir.openDir(Io.Dir.cwd(), init.io, ".", .{
        .access_sub_paths = true,
        .iterate = true,
        .follow_symlinks = false,
    });

    var scanner: FileIterator(Context) = try .init(
        init.gpa,
        init.io,
        &paths,
        .{},
        Pathnames.ROOT,
        dir,
    );
    defer scanner.deinit();

    while (try scanner.next()) |item| {
        print("{f}\n", .{pw.fmt(item.path)});
    }
}
