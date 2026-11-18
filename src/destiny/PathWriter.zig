const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @import("Interned.zig");
const Pathnames = @import("Pathnames.zig");
const PathIndexer = @import("PathIndexer.zig");

const PathWriter = @This();
const Error = error{WriteFailed} || Allocator.Error;

allocator: Allocator,
pathnames: *Pathnames,

path_buf: std.ArrayList(u32) = .empty,

pub fn init(allocator: Allocator, pathnames: *Pathnames) PathWriter {
    return .{ .allocator = allocator, .pathnames = pathnames };
}

pub fn deinit(self: *PathWriter) void {
    self.path_buf.deinit(self.allocator);
}

pub fn writePath(self: *PathWriter, writer: *std.Io.Writer, path: u32) Error!void {
    var current = path;
    self.path_buf.items.len = 0;
    while (current != Pathnames.ROOT) {
        const elt = self.pathnames.get(current);
        try self.path_buf.append(self.allocator, elt.name);
        current = elt.parent;
    }
    var pos = self.path_buf.items.len;
    while (pos != 0) {
        pos -= 1;
        try writer.writeAll(self.pathnames.int.get(self.path_buf.items[pos]));
        if (pos != 0)
            try writer.writeByte('/');
    }
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
    try std.testing.expectEqual(4, ulb_id);
    const uls_id = try indexer.index("/usr/local/share");
    try std.testing.expectEqual(5, uls_id);
    const ul_id = try indexer.index("/usr/local");
    try std.testing.expectEqual(3, ul_id);

    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try pw.writePath(&writer, ulb_id);
    try writer.flush();

    try std.testing.expectEqualDeep("/usr/local/bin", writer.buffered());
}
