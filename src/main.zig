const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");

test {
    _ = @import("destiny/Interned.zig");
    _ = @import("destiny/Pathnames.zig");
}

pub const PathIndexer = struct {
    const Self = @This();
    allocator: Allocator,
    pathnames: *Pathnames,
    path_nodes: std.ArrayList(u32) = .empty,

    pub fn init(allocator: Allocator, pathnames: *Pathnames) Self {
        return .{ .allocator = allocator, .pathnames = pathnames };
    }

    pub fn deinit(self: *Self) void {
        self.path_nodes.deinit(self.allocator);
    }

    pub fn index(self: *Self, pathname: []const u8) Allocator.Error!u32 {
        var iter = std.mem.splitScalar(u8, pathname, '/');
        var current = Pathnames.ROOT;
        var pos: usize = 0;
        const items = &self.path_nodes.items;

        // Skip over common prefix
        while (iter.next()) |name| : (pos += 1) {
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
};

test PathIndexer {
    var int: Interned = try .init(std.testing.allocator);
    defer int.deinit();
    var paths: Pathnames = try .init(std.testing.allocator, &int);
    defer paths.deinit();
    var indexer: PathIndexer = .init(std.testing.allocator, &paths);
    defer indexer.deinit();

    const ulb_id = try indexer.index("/usr/local/bin");
    try std.testing.expectEqual(4, ulb_id);
    const uls_id = try indexer.index("/usr/local/share");
    try std.testing.expectEqual(5, uls_id);
    const ul_id = try indexer.index("/usr/local");
    try std.testing.expectEqual(3, ul_id);

    try std.testing.expectEqual(3, paths.get(ulb_id).parent);
    try std.testing.expectEqual(3, paths.get(uls_id).parent);
}

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
