const std = @import("std");
const cli = @import("cli");

const Io = std.Io;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const HashMapUnmanaged = std.hash_map.HashMapUnmanaged;

const K = @import("../destiny/constants.zig");
const Pathnames = @import("../destiny/Pathnames.zig");
const PathWriter = @import("../destiny/PathWriter.zig");
const Manifest = @import("../destiny/Manifest.zig");
const Object = @import("../destiny/Object.zig");

const Self = @This();
const Args = cli.Parsed(command);

allocator: Allocator,
io: Io,
pathnames: *Pathnames,
args: Args,

path_writer: PathWriter,

pub const Error = Manifest.AppendError ||
    Manifest.LoadError ||
    PathWriter.Error ||
    Io.Dir.HardLinkError ||
    Io.Dir.DeleteFileError ||
    Io.Dir.RenameError;

pub fn init(allocator: Allocator, io: Io, pathnames: *Pathnames, args: Args) Self {
    return .{
        .allocator = allocator,
        .io = io,
        .pathnames = pathnames,
        .args = args,
        .path_writer = .init(allocator, pathnames),
    };
}

pub fn deinit(self: *Self) void {
    self.path_writer.deinit();
}

fn fmtPath(self: *Self, path: Pathnames.Handle) PathWriter.Fmt {
    return self.path_writer.fmt(path);
}

fn findBestInode(self: *Self, gpa: Allocator, manifest: *Manifest, handle: Manifest.Handle) Error!?Object {
    const Item = struct {
        object: Object,
        depth: usize,
        count: usize,

        fn betterThan(me: @This(), other: ?@This()) bool {
            if (other) |o|
                return me.count > o.count or
                    (me.count == o.count and me.depth < o.depth);
            return true;
        }
    };

    var survey: HashMapUnmanaged(Io.File.INode, Item, Manifest.IntContext(Io.File.INode), 80) = .empty;
    defer survey.deinit(gpa);

    var item_iter = try manifest.hashHandleIter(handle);
    while (item_iter.next()) |object| {
        // Don't bother linking zero byte objects
        if (object.size == 0)
            return null;
        const slot = try survey.getOrPutContext(gpa, object.inode, .{});
        const depth = self.pathnames.depth(object.path);
        if (slot.found_existing) {
            slot.value_ptr.count += 1;
            if (depth <= slot.value_ptr.depth) {
                slot.value_ptr.depth = depth;
                slot.value_ptr.object = object;
            }
        } else {
            slot.value_ptr.* = .{
                .object = object,
                .depth = depth,
                .count = 1,
            };
        }
    }

    assert(survey.count() > 0);

    if (survey.count() == 1)
        return null;

    var best: ?Item = null;
    var survey_iter = survey.iterator();
    while (survey_iter.next()) |entry| {
        const item = entry.value_ptr.*;
        if (item.betterThan(best))
            best = item;
    }

    return best.?.object;
}

fn linkFile(self: *Self, gpa: Allocator, dir: Io.Dir, best_path: []const u8, object: Object) Error!void {
    var object_path = try self.path_writer.toArrayList(gpa, object.path);
    defer object_path.deinit(gpa);
    const tmp = try self.pathnames.internPeerName(object.path, K.TMP_NAME);
    var tmp_path = try self.path_writer.toArrayList(gpa, tmp);
    defer tmp_path.deinit(gpa);

    std.log.info("    ➡️ {s}", .{object_path.items});
    const options: Io.Dir.HardLinkOptions = .{ .follow_symlinks = false };
    dir.hardLink(best_path, dir, tmp_path.items, self.io, options) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try dir.deleteFile(self.io, tmp_path.items);
            try dir.hardLink(best_path, dir, tmp_path.items, self.io, options);
        },
        else => return err,
    };
    try dir.rename(tmp_path.items, dir, object_path.items, self.io);
}

fn linkItem(self: *Self, dir: Io.Dir, manifest: *Manifest, handle: Manifest.Handle) Error!void {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const args = self.args.kind.args;
    if (try self.findBestInode(gpa, manifest, handle)) |best| {
        var best_path = try self.path_writer.toArrayList(gpa, best.path);
        defer best_path.deinit(gpa);
        std.log.info("  {s} ➡️", .{best_path.items});

        var item_iter = try manifest.hashHandleIter(handle);
        while (item_iter.next()) |object| {
            if (object.inode == best.inode) continue;
            if (args.@"dry-run") {
                std.log.info("    ➡️ {f}", .{self.fmtPath(object.path)});
            } else {
                try self.linkFile(gpa, dir, best_path.items, object);
            }
        }
    }
}

fn link(self: *Self, root: []const u8) Error!void {
    const openOptions: Io.Dir.OpenOptions = .{ .follow_symlinks = false };
    const dir: Io.Dir = blk: {
        if (std.fs.path.isAbsolute(root))
            break :blk try Io.Dir.openDirAbsolute(self.io, root, openOptions);
        break :blk try Io.Dir.cwd().openDir(self.io, root, openOptions);
    };
    defer dir.close(self.io);

    var manifest: Manifest = .init(self.allocator, self.pathnames);
    defer manifest.deinit();

    try manifest.load(self.io, dir, K.MANIFEST);

    var hash_iter = (try manifest.hashIndex()).index.iterator();
    while (hash_iter.next()) |entry| {
        try self.linkItem(dir, &manifest, entry.value_ptr.*);
    }
}

pub fn run(self: *Self) Error!void {
    const args = self.args.kind.args;

    for (args.dir) |root| {
        std.log.info("Linking {s}", .{root});
        try self.link(root);
    }
}

const help_short = "Hard link files that have the same contents.";

pub const command: cli.Command = .{
    .name = .link,
    .help = help_short ++ "\n\nWhen multiple directories / manifests are specified, link each individually.\n",
    .help_short = help_short,
    .positional_args = &.{.init(
        .dir,
        []const []const u8,
        .{
            .help = "Directory to operate on. May be specified more than once.",
            .count = .unlimited,
            .default_value = &.{"."},
        },
    )},
    .named_args = &.{
        .init(.@"dry-run", bool, .{
            .help = "Just report what would be done.",
            .default_value = false,
        }),
    },
};

test {
    std.testing.refAllDecls(@This());
}
