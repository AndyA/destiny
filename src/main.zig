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

pub const FileIterator = struct {
    const Self = @This();

    const Error = Allocator.Error || Io.Dir.Reader.Error || Io.Dir.OpenError;

    const Frame = struct {
        path: Pathnames.Handle,
        dir: Io.Dir,
        iter: Io.Dir.Iterator,
    };

    const Item = struct {
        path: Pathnames.Handle,
        dir: Io.Dir,
        entry: Io.Dir.Entry,
    };

    allocator: Allocator,
    io: Io,
    pathnames: *Pathnames,
    stack: std.ArrayList(Frame) = .empty,

    pub fn init(allocator: Allocator, io: Io, pathnames: *Pathnames) Self {
        return .{
            .allocator = allocator,
            .io = io,
            .pathnames = pathnames,
        };
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

    fn pop(self: *Self) Frame {
        assert(self.stack.items.len != 0);
        defer self.stack.items.len -= 1;
        return self.stack.items[self.stack.items.len - 1];
    }

    fn topOfStack(self: *const Self) ?*Frame {
        if (self.stack.items.len == 0) return null;
        return &self.stack.items[self.stack.items.len - 1];
    }

    pub fn start(self: *Self, dir: Io.Dir) Error!void {
        try self.push(Pathnames.ROOT, dir);
    }

    fn descend(self: *Self, tos: *const Frame, item: Item) Error!void {
        const sub_dir = try tos.dir.openDir(self.io, item.entry.name, .{
            .access_sub_paths = true,
            .iterate = true,
            .follow_symlinks = false,
        });
        try self.push(item.path, sub_dir);
    }

    pub fn next(self: *Self) Error!?Item {
        while (true) {
            if (self.topOfStack()) |tos| {
                if (try tos.iter.next(self.io)) |entry| {
                    const path = try self.pathnames.intern(tos.path, entry.name);
                    const item: Item = .{ .path = path, .dir = tos.dir, .entry = entry };
                    switch (entry.kind) {
                        .directory => try self.descend(tos, item),
                        else => return item,
                    }
                } else {
                    self.pop().dir.close(self.io);
                }
            } else {
                return null;
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
    var scanner: FileIterator = .init(init.gpa, init.io, &paths);
    defer scanner.deinit();

    const root = try Io.Dir.openDirAbsolute(init.io, "/Users/andy/Works/zig/destiny", .{
        .access_sub_paths = true,
        .iterate = true,
        .follow_symlinks = false,
    });

    try scanner.start(root);
    while (try scanner.next()) |item| {
        print("{f}\n", .{pw.fmt(item.path)});
    }
}
