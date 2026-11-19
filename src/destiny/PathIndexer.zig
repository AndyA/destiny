const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Pathnames = @import("Pathnames.zig");

const PathIndexer = @This();
allocator: Allocator,
pathnames: *Pathnames,
root: Pathnames.Handle,
path_nodes: std.ArrayList(Pathnames.Handle) = .empty,

pub fn initBelow(
    allocator: Allocator,
    pathnames: *Pathnames,
    root: Pathnames.Handle,
) PathIndexer {
    return .{ .allocator = allocator, .pathnames = pathnames, .root = root };
}

pub fn init(allocator: Allocator, pathnames: *Pathnames) PathIndexer {
    return initBelow(allocator, pathnames, Pathnames.ROOT);
}

pub fn deinit(self: *PathIndexer) void {
    self.path_nodes.deinit(self.allocator);
}

pub fn index(self: *PathIndexer, pathname: []const u8) Allocator.Error!Pathnames.Handle {
    var current = self.root;
    var pos: usize = 0;

    var iter = std.mem.splitScalar(u8, pathname, '/');
    // Skip over common prefix
    while (iter.next()) |name| : (pos += 1) {
        const items = &self.path_nodes.items;
        if (pos < items.len) {
            const other = self.pathnames.getElementName(items.*[pos]);
            // Re-use common prefix
            if (std.mem.eql(u8, name, other)) {
                current = items.*[pos];
                continue;
            }
            items.len = pos;
        }
        current = try self.pathnames.intern(current, name);
        try self.path_nodes.append(self.allocator, current);
    }

    return current;
}

test PathIndexer {
    var int: @import("Interned.zig") = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();
    var indexer: PathIndexer = .init(std.testing.allocator, &paths);
    defer indexer.deinit();

    const ulb_id = try indexer.index("/usr/local/bin");
    try std.testing.expectEqual(@as(Pathnames.Handle, @fromBackingInt(4)), ulb_id);
    const uls_id = try indexer.index("/usr/local/share");
    try std.testing.expectEqual(@as(Pathnames.Handle, @fromBackingInt(5)), uls_id);
    const ul_id = try indexer.index("/usr/local");
    try std.testing.expectEqual(@as(Pathnames.Handle, @fromBackingInt(3)), ul_id);

    try std.testing.expectEqual(@as(Pathnames.Handle, @fromBackingInt(3)), paths.get(ulb_id).parent);
    try std.testing.expectEqual(@as(Pathnames.Handle, @fromBackingInt(3)), paths.get(uls_id).parent);
}
