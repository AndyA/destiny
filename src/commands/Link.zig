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
    Manifest.LoadError;

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

fn findBestInode(self: *Self, manifest: *Manifest, handle: Manifest.Handle) Error!?Object {
    var arena: std.heap.ArenaAllocator = .init(self.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const Item = struct {
        object: Object,
        depth: usize,
        count: usize,
    };

    var inode_survey: HashMapUnmanaged(Io.File.INode, Item, Manifest.IntContext(Io.File.INode), 80) = .empty;
    defer inode_survey.deinit(gpa);

    var item_iter = try manifest.hashHandleIter(handle);
    while (item_iter.next()) |object| {
        const slot = try inode_survey.getOrPutContext(gpa, object.inode, .{});
        const depth = self.pathnames.depth(object.path);
        if (slot.found_existing) {
            slot.value_ptr.count += 1;
            if (depth < slot.value_ptr.depth) {
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

    assert(inode_survey.count() > 0);

    if (inode_survey.count() == 1)
        return null;

    var best: ?Item = null;
    var survey_iter = inode_survey.iterator();
    while (survey_iter.next()) |item| {
        if (best == null or item.value_ptr.count > best.?.count) {
            best = item.value_ptr.*;
        }
    }

    return best.?.object;
}

fn linkItem(self: *Self, manifest: *Manifest, handle: Manifest.Handle) Error!void {
    if (try self.findBestInode(manifest, handle)) |best| {
        const sample = manifest.get(handle);
        std.log.info("  {x:0>64}", .{sample.hash});

        {
            var item_iter = try manifest.hashHandleIter(handle);
            while (item_iter.next()) |object| {
                std.log.info(
                    "    {d:>12} {f} -> {f}",
                    .{ object.inode, self.fmtPath(best.path), self.fmtPath(object.path) },
                );
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
        try self.linkItem(&manifest, entry.value_ptr.*);
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
