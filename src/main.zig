const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");

test {
    _ = @import("destiny/Interned.zig");
    _ = @import("destiny/Pathnames.zig");
    _ = @import("destiny/PathIndexer.zig");
    _ = @import("destiny/PathWriter.zig");
    _ = @import("destiny/Manifest.zig");
}

pub const Scanner = struct {
    const Self = @This();

    const Error = Allocator.Error || Io.Dir.Reader.Error || Io.Dir.OpenError;

    const Frame = struct {
        path: Pathnames.Handle,
        dir: Io.Dir,
        iter: Io.Dir.Iterator,
        path_len: usize,
    };

    allocator: Allocator,
    io: Io,
    pathnames: *Pathnames,
    stack: std.ArrayList(Frame) = .empty,
    current_path: std.ArrayList(u8) = .empty,

    pub fn init(allocator: Allocator, io: Io, pathnames: *Pathnames) Self {
        return .{
            .allocator = allocator,
            .io = io,
            .pathnames = pathnames,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
        self.current_path.deinit(self.allocator);
    }

    fn push(self: *Self, frame: Frame) Allocator.Error!void {
        try self.stack.append(self.allocator, frame);
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

    pub fn scan(self: *Self, dir: Io.Dir) Error!void {
        try self.push(.{
            .path = Pathnames.ROOT,
            .dir = dir,
            .iter = dir.iterate(),
            .path_len = self.current_path.items.len,
        });
        while (self.topOfStack()) |tos| {
            if (try tos.iter.next(self.io)) |item| {
                const path_len = self.current_path.items.len;
                if (item.name[0] == '.')
                    continue;
                const item_path = try self.pathnames.intern(tos.path, item.name);
                switch (item.kind) {
                    .file => {
                        defer self.current_path.items.len = path_len;
                        try self.current_path.appendSlice(self.allocator, item.name);
                        print("{s}\n", .{self.current_path.items});
                    },
                    .directory => {
                        try self.current_path.appendSlice(self.allocator, item.name);
                        try self.current_path.append(self.allocator, '/');
                        const sub_dir = try tos.dir.openDir(self.io, item.name, .{
                            .access_sub_paths = false,
                            .iterate = true,
                            .follow_symlinks = false,
                        });
                        try self.push(.{
                            .path = item_path,
                            .dir = sub_dir,
                            .iter = sub_dir.iterate(),
                            .path_len = path_len,
                        });
                    },
                    else => {},
                }
            } else {
                const frame = self.pop();
                frame.dir.close(self.io);
                self.current_path.items.len = frame.path_len;
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var int: Interned = try .init(init.gpa);
    defer int.deinit();
    var paths: Pathnames = try .init(init.gpa, &int);
    defer paths.deinit();
    var scanner: Scanner = .init(init.gpa, init.io, &paths);
    defer scanner.deinit();
    if (true) {
        const root = try Io.Dir.openDirAbsolute(init.io, "/Users/andy/Works/zig/destiny", .{
            .access_sub_paths = false,
            .iterate = true,
            .follow_symlinks = false,
        });
        try scanner.scan(root);
    } else {
        try scanner.scan(Io.Dir.cwd());
    }
}
