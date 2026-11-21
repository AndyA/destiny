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

// const Entry = struct {
//     name: []const u8,
//     kind: Io.File.Kind,
//     inode: Io.File.INode,
// };

const DirEntry = struct {
    name: Interned.Handle,
    path: Pathnames.Handle,
    kind: Io.File.Kind,
    inode: Io.File.INode,
};

const FileIteratorItem = struct {
    entry: DirEntry,
    dir: Io.Dir,
};

pub fn FileIterator(comptime Context: type, comptime openOptions: Io.Dir.OpenOptions) type {
    return struct {
        const Self = @This();

        const Error = Allocator.Error || Io.Dir.Reader.Error || Io.Dir.OpenError;

        const Frame = struct {
            path: Pathnames.Handle,
            dir: Io.Dir,
            iter: Io.Dir.Iterator,
            loaded: bool = false,
        };

        const Options = struct {
            path: Pathnames.Handle = Pathnames.ROOT,
            sorted: bool = false,
            ctx: Context = .{},
        };

        allocator: Allocator,
        io: Io,
        pathnames: *Pathnames,
        options: Options,
        stack: std.ArrayList(Frame) = .empty,

        // These two are only used in sorted mode
        dir_buf: std.ArrayList(DirEntry) = .empty,
        dir_pos: usize = 0,

        pub fn init(
            allocator: Allocator,
            io: Io,
            pathnames: *Pathnames,
            dir: Io.Dir,
            options: Options,
        ) Allocator.Error!Self {
            var self: Self = .{
                .allocator = allocator,
                .io = io,
                .pathnames = pathnames,
                .options = options,
            };
            try self.push(options.path, dir);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit(self.allocator);
            self.dir_buf.deinit(self.allocator);
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
            const name = self.pathnames.int.get(item.entry.name);
            const sub_dir = try tos.dir.openDir(self.io, name, openOptions);
            try self.push(item.entry.path, sub_dir);
        }

        fn shouldInclude(self: *const Self, item: FileIteratorItem) bool {
            if (@typeInfo(Context) == .@"struct" and @hasDecl(Context, "shouldInclude")) {
                return self.options.ctx.shouldInclude(item, self.pathnames.int.get(item.entry.name));
            }
            return true;
        }

        fn tosItem(self: *Self, tos: *Frame, entry: Io.Dir.Entry) Allocator.Error!FileIteratorItem {
            const name = try self.pathnames.int.intern(entry.name);
            const path = try self.pathnames.internHandle(tos.path, name);
            return .{
                .entry = .{
                    .name = name,
                    .path = path,
                    .kind = entry.kind,
                    .inode = entry.inode,
                },
                .dir = tos.dir,
            };
        }

        fn loadDir(self: *Self, tos: *Frame) Error!void {
            self.dir_buf.items.len = 0;
            self.dir_pos = 0;
            while (try tos.iter.next(self.io)) |entry| {
                const item = try self.tosItem(tos, entry);
                if (!self.shouldInclude(item))
                    continue;
                try self.dir_buf.append(self.allocator, item.entry);
            }
        }

        fn sortDir(self: *Self) void {
            const Ctx = struct {
                int: *Interned,
                pub fn lessThan(me: @This(), lhs: DirEntry, rhs: DirEntry) bool {
                    return std.mem.lessThan(u8, me.int.get(lhs.name), me.int.get(rhs.name));
                }
            };
            const ctx: Ctx = .{ .int = self.pathnames.int };
            std.mem.sortUnstable(DirEntry, self.dir_buf.items, ctx, Ctx.lessThan);
        }

        fn nextSorted(self: *Self) Error!?FileIteratorItem {
            while (true) {
                if (self.topOfStack()) |tos| {
                    if (!tos.loaded) {
                        try self.loadDir(tos);
                        self.sortDir();
                        tos.loaded = true;
                    }
                    if (self.dir_pos < self.dir_buf.items.len) {
                        const entry = self.dir_buf.items[self.dir_pos];
                        self.dir_pos += 1;
                        const item: FileIteratorItem = .{ .entry = entry, .dir = tos.dir };
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

        fn nextUnsorted(self: *Self) Error!?FileIteratorItem {
            while (true) {
                if (self.topOfStack()) |tos| {
                    if (try tos.iter.next(self.io)) |entry| {
                        const item = try self.tosItem(tos, entry);
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

        pub fn next(self: *Self) Error!?FileIteratorItem {
            return switch (self.options.sorted) {
                false => self.nextUnsorted(),
                true => self.nextSorted(),
            };
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

        pub fn shouldInclude(_: @This(), _: FileIteratorItem, name: []const u8) bool {
            if (name.len > 0 and name[0] == '.')
                return false;
            if (isManifest(name))
                return false;
            return true;
        }
    };

    const openOptions: Io.Dir.OpenOptions = .{ .follow_symlinks = false, .iterate = true };
    const dir = try Io.Dir.openDir(Io.Dir.cwd(), init.io, ".", openOptions);
    var scanner: FileIterator(Context, openOptions) = try .init(
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
}
