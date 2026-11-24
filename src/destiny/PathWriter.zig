const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @import("Interned.zig");
const Pathnames = @import("Pathnames.zig");
const PathIndexer = @import("PathIndexer.zig");

const PathWriter = @This();
pub const Error = error{WriteFailed} || Allocator.Error;

pub const Fmt = struct {
    pw: *PathWriter,
    path: Pathnames.Handle,

    pub fn format(self: @This(), writer: *Io.Writer) Io.Writer.Error!void {
        self.pw.writePath(writer, self.path) catch return error.WriteFailed;
    }
};

allocator: Allocator,
pathnames: *Pathnames,

path_buf: std.ArrayList(Interned.Handle) = .empty,

pub fn init(allocator: Allocator, pathnames: *Pathnames) PathWriter {
    return .{ .allocator = allocator, .pathnames = pathnames };
}

pub fn deinit(self: *PathWriter) void {
    self.path_buf.deinit(self.allocator);
}

fn buildPath(self: *PathWriter, path: Pathnames.Handle) Error!void {
    var current = path;
    self.path_buf.items.len = 0;
    while (current != Pathnames.ROOT) {
        const elt = self.pathnames.get(current);
        try self.path_buf.append(self.allocator, elt.name);
        current = elt.parent;
    }
}

pub fn writePath(self: *PathWriter, writer: *Io.Writer, path: Pathnames.Handle) Error!void {
    try self.buildPath(path);
    var pos = self.path_buf.items.len;
    while (pos != 0) {
        pos -= 1;
        try writer.writeAll(self.pathnames.int.get(self.path_buf.items[pos]));
        if (pos != 0)
            try writer.writeByte('/');
    }
}

pub fn writePathJson(self: *PathWriter, writer: *Io.Writer, path: Pathnames.Handle) Error!void {
    try self.buildPath(path);
    var pos = self.path_buf.items.len;
    while (pos != 0) {
        pos -= 1;
        const elt = self.pathnames.int.get(self.path_buf.items[pos]);
        try std.json.Stringify.encodeJsonStringChars(elt, .{}, writer);
        if (pos != 0)
            try writer.writeByte('/');
    }
}

pub fn fmt(self: *PathWriter, path: Pathnames.Handle) Fmt {
    return .{ .pw = self, .path = path };
}

test PathWriter {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();
    var indexer: PathIndexer = .init(std.testing.allocator, &paths);
    defer indexer.deinit();
    var pw: PathWriter = .init(std.testing.allocator, &paths);
    defer pw.deinit();

    const ulb_id = try indexer.index("/usr/local/bin");

    var buf: [256]u8 = undefined;
    var writer: Io.Writer = .fixed(&buf);
    try pw.writePath(&writer, ulb_id);
    try writer.flush();

    try std.testing.expectEqualDeep("/usr/local/bin", writer.buffered());
}
