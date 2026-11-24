const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("Interned.zig");
const Pathnames = @import("Pathnames.zig");
const PathWriter = @import("PathWriter.zig");

const DirEntry = struct {
    name: Interned.Handle,
    path: Pathnames.Handle,
    kind: Io.File.Kind,
    inode: Io.File.INode,
};

pub const FileIteratorItem = struct {
    entry: DirEntry,
    dir: Io.Dir,
};

pub fn FileIterator(comptime Context: type, comptime openOptions: Io.Dir.OpenOptions) type {
    return struct {
        const Self = @This();

        pub const Error = Allocator.Error || Io.Dir.Reader.Error || Io.Dir.OpenError;

        const Frame = struct {
            path: Pathnames.Handle,
            dir: Io.Dir,
            iter: Io.Dir.Iterator,
            // Only used in sorted mode
            dir_limit: usize,
            dir_pos: usize,
            loaded: bool = false,
        };

        pub const Options = struct {
            path: Pathnames.Handle = Pathnames.ROOT,
            sorted: bool = false,
        };

        allocator: Allocator,
        io: Io,
        pathnames: *Pathnames,
        ctx: Context,
        options: Options,
        stack: std.ArrayList(Frame) = .empty,

        // Only used in sorted mode
        dir_buf: std.ArrayList(DirEntry) = .empty,

        pub fn init(
            allocator: Allocator,
            io: Io,
            pathnames: *Pathnames,
            dir: Io.Dir,
            ctx: Context,
            options: Options,
        ) Allocator.Error!Self {
            var self: Self = .{
                .allocator = allocator,
                .io = io,
                .pathnames = pathnames,
                .ctx = ctx,
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
            const dir_limit = self.dir_buf.items.len;
            try self.stack.append(self.allocator, .{
                .path = path,
                .dir = dir,
                .iter = dir.iterate(),
                .dir_limit = dir_limit,
                .dir_pos = dir_limit,
            });
        }

        fn pop(self: *Self) void {
            assert(self.stack.items.len != 0);
            defer self.stack.items.len -= 1;
            const frame = self.stack.items[self.stack.items.len - 1];
            self.dir_buf.items.len = frame.dir_limit;
            if (self.stack.items.len > 1)
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
                return self.ctx.shouldInclude(item, self.pathnames.int.get(item.entry.name));
            }
            return true;
        }

        fn makeIteratorItem(
            self: *Self,
            tos: *Frame,
            entry: Io.Dir.Entry,
        ) Allocator.Error!FileIteratorItem {
            const name = try self.pathnames.int.internSlice(entry.name);
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

        /// Iterate over a directory, interning names and paths and appending the
        /// resulting entries to `dir_buf`. Previous items in `dir_buf` are
        /// unaffected (they belong to a parent directory).
        fn loadDir(self: *Self, tos: *Frame) Error!void {
            assert(self.dir_buf.items.len == tos.dir_limit);
            while (try tos.iter.next(self.io)) |entry| {
                const item = try self.makeIteratorItem(tos, entry);
                if (!self.shouldInclude(item))
                    continue;
                try self.dir_buf.append(self.allocator, item.entry);
            }
        }

        /// Sort the buffered directory entries between `tos.dir_limit` and the end
        /// of the buffer - i.e. the most recently read directory.
        fn sortDir(self: *Self, tos: *const Frame) void {
            const Ctx = struct {
                int: *Interned,
                pub fn lessThan(me: @This(), lhs: DirEntry, rhs: DirEntry) bool {
                    return std.mem.lessThan(u8, me.int.get(lhs.name), me.int.get(rhs.name));
                }
            };
            const ctx: Ctx = .{ .int = self.pathnames.int };
            std.mem.sortUnstable(
                DirEntry,
                self.dir_buf.items[tos.dir_limit..],
                ctx,
                Ctx.lessThan,
            );
        }

        fn nextSorted(self: *Self) Error!?FileIteratorItem {
            while (true) {
                if (self.topOfStack()) |tos| {
                    if (!tos.loaded) {
                        assert(tos.dir_limit == self.dir_buf.items.len);
                        try self.loadDir(tos);
                        self.sortDir(tos);
                        tos.loaded = true;
                    }
                    if (tos.dir_pos < self.dir_buf.items.len) {
                        const entry = self.dir_buf.items[tos.dir_pos];
                        tos.dir_pos += 1;
                        const item: FileIteratorItem = .{ .entry = entry, .dir = tos.dir };
                        if (entry.kind == .directory)
                            try self.descend(tos, item);
                        return item;
                    }
                    self.pop();
                } else {
                    assert(self.dir_buf.items.len == 0);
                    return null;
                }
            }
        }

        fn nextUnsorted(self: *Self) Error!?FileIteratorItem {
            while (true) {
                if (self.topOfStack()) |tos| {
                    if (try tos.iter.next(self.io)) |entry| {
                        const item = try self.makeIteratorItem(tos, entry);
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
