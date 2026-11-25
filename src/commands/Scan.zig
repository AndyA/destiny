const std = @import("std");
const cli = @import("cli");

const Io = std.Io;
const assert = std.debug.assert;
// const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("../destiny/Interned.zig");
const Pathnames = @import("../destiny/Pathnames.zig");
const PathWriter = @import("../destiny/PathWriter.zig");
const Manifest = @import("../destiny/Manifest.zig");
const Object = @import("../destiny/Object.zig");
const fi = @import("../destiny/file_iterator.zig");
const sha256File = @import("../destiny/tools.zig").sha256File;

const MANIFEST = "MANIFEST.json";
const SNAPSHOT = "MANIFEST.SNAPSHOT.json";

const Self = @This();
const Args = cli.Parsed(command);

pub const openOptions: Io.Dir.OpenOptions = .{
    .follow_symlinks = false,
    .iterate = true,
};

pub const Error = Manifest.AppendError ||
    Manifest.LoadError ||
    Manifest.SaveError ||
    fi.FileIteratorError ||
    Io.File.StatError ||
    Io.Dir.DeleteFileError;

allocator: Allocator,
io: Io,
pathnames: *Pathnames,
args: Args,

path_writer: PathWriter,
search: std.ArrayList(Manifest) = .empty,

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
    for (self.search.items) |*item|
        item.deinit();
    self.search.deinit(self.allocator);
    self.path_writer.deinit();
}

fn fmtPath(self: *Self, path: Pathnames.Handle) PathWriter.Fmt {
    return self.path_writer.fmt(path);
}

fn objectMatches(self: *const Self, object: Object, stat: Io.File.Stat) bool {
    const args = self.args.kind.args;
    return object.size == stat.size and
        (!args.perms or object.permissions == stat.permissions) and
        (!args.mtime or object.mtime.nanoseconds == stat.mtime.nanoseconds);
}

fn matchInManifest(
    self: *const Self,
    manifest: *Manifest,
    path: Pathnames.Handle,
    stat: Io.File.Stat,
) Error!?Object {
    if (try manifest.findPathname(path)) |found| {
        if (self.objectMatches(found, stat))
            return found;
    }
    if (try manifest.findINode(stat.inode)) |found| {
        if (self.objectMatches(found, stat))
            return found;
    }
    return null;
}

fn matchObject(self: *Self, path: Pathnames.Handle, stat: Io.File.Stat) Error!?Object {
    for (self.search.items) |*manifest| {
        if (try self.matchInManifest(manifest, path, stat)) |found|
            return found;
    }
    return null;
}

fn createObject(self: *Self, manifest: *Manifest, item: fi.FileIteratorItem) Error!?Object {
    if (try manifest.findINode(item.entry.inode)) |found| {
        var object = found;
        object.path = item.entry.path;
        return object;
    }

    const name = self.pathnames.int.get(item.entry.name);
    const file = item.dir.openFile(self.io, name, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close(self.io);

    const stat = try file.stat(self.io);

    const hash = blk: {
        if (try self.matchObject(item.entry.path, stat)) |found|
            break :blk found.hash;

        const sha256 = try sha256File(self.io, file);
        std.log.info("  {x:0>64} {f}", .{ sha256, self.fmtPath(item.entry.path) });

        break :blk sha256;
    };

    return .{
        .path = item.entry.path,
        .inode = item.entry.inode,
        .size = stat.size,
        .permissions = stat.permissions,
        .kind = item.entry.kind,
        .mtime = stat.mtime,
        .hash = hash,
    };
}

fn isManifest(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "MANIFEST.") and
        std.mem.endsWith(u8, name, ".json");
}

pub fn shouldInclude(_: @This(), _: fi.FileIteratorItem, name: []const u8) bool {
    if (name.len > 0 and name[0] == '.')
        return false;
    if (isManifest(name))
        return false;
    return true;
}

fn addToSearch(self: *Self, dir: Io.Dir, name: []const u8, root: Pathnames.Handle) Error!void {
    var manifest: Manifest = .init(self.allocator, self.pathnames);
    errdefer manifest.deinit();
    try manifest.loadBelow(self.io, dir, name, root);
    try self.search.append(self.allocator, manifest);
}

fn maybeAddToSearch(self: *Self, dir: Io.Dir, name: []const u8, root: Pathnames.Handle) Error!void {
    self.addToSearch(dir, name, root) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}

fn scanDir(self: *Self, manifest: *Manifest, dir: Io.Dir) Error!void {
    const args = self.args.kind.args;
    var iter: fi.FileIterator(Self, openOptions) = try .init(
        self.allocator,
        self.io,
        self.pathnames,
        dir,
        self.*,
        .{ .sorted = args.sort },
    );
    defer iter.deinit();

    var snapshot_time: std.Io.Timestamp = .now(self.io, .awake);

    while (try iter.next()) |item| {
        switch (item.entry.kind) {
            .file => {
                if (try self.createObject(manifest, item)) |object|
                    try manifest.append(object);
            },
            .directory => std.log.info("Scanning {f}", .{self.fmtPath(item.entry.path)}),
            else => |kind| std.log.info(
                "  Skipping {s} {f}",
                .{ @tagName(kind), self.fmtPath(item.entry.path) },
            ),
        }
        if (args.snapshot) |snap| {
            const deadline = snapshot_time.addDuration(.fromSeconds(snap));
            const now: std.Io.Timestamp = .now(self.io, .awake);
            if (now.nanoseconds >= deadline.nanoseconds) {
                try manifest.save(self.io, dir, SNAPSHOT);
                snapshot_time = now;
            }
        }
    }
}

fn scanNestedManifests(self: *Self, dir: Io.Dir) Error!void {
    const args = self.args.kind.args;
    const Context = struct {
        pub fn shouldInclude(_: @This(), _: fi.FileIteratorItem, name: []const u8) bool {
            if (name.len > 0 and name[0] == '.')
                return false;
            return true;
        }
    };
    var iter: fi.FileIterator(Context, openOptions) = try .init(
        self.allocator,
        self.io,
        self.pathnames,
        dir,
        .{},
        .{ .max_depth = args.@"max-nested-depth" orelse std.math.maxInt(usize) },
    );
    defer iter.deinit();

    while (try iter.next()) |item| {
        switch (item.entry.kind) {
            .file => {
                const elt: Pathnames.PathElement = self.pathnames.get(item.entry.path);
                const name = self.pathnames.int.get(elt.name);
                if (elt.parent != Pathnames.ROOT and isManifest(name)) {
                    std.log.info("Adding {f} to search path", .{self.fmtPath(item.entry.path)});
                    try self.addToSearch(item.dir, name, elt.parent);
                }
            },
            else => {},
        }
    }
}

pub fn scan(self: *Self, root: []const u8) Error!void {
    const args = self.args.kind.args;

    const dir: Io.Dir = blk: {
        if (std.fs.path.isAbsolute(root))
            break :blk try Io.Dir.openDirAbsolute(self.io, root, openOptions);
        break :blk try Io.Dir.cwd().openDir(self.io, root, openOptions);
    };
    defer dir.close(self.io);

    if (args.@"use-nested")
        try self.scanNestedManifests(dir);

    try self.maybeAddToSearch(dir, MANIFEST, Pathnames.ROOT);
    try self.maybeAddToSearch(dir, SNAPSHOT, Pathnames.ROOT);

    var manifest: Manifest = .init(self.allocator, self.pathnames);
    defer manifest.deinit();

    try self.scanDir(&manifest, dir);

    std.log.info("Saving {s}", .{MANIFEST});
    try manifest.save(self.io, dir, MANIFEST);

    dir.deleteFile(self.io, SNAPSHOT) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

pub fn run(self: *Self) !void {
    const args = self.args.kind.args;
    for (args.use) |use| {
        try self.addToSearch(Io.Dir.cwd(), use, Pathnames.ROOT);
    }
    for (args.root) |root| {
        std.log.info("Scanning {s}", .{root});
        try self.scan(root);
    }
}

pub const command: cli.Command = .{
    .name = .scan,
    .help = "Create or update one or more MANIFESTs.\n" ++
        "When multiple directories / manifests are specified update each individually.",
    .help_short = "Create or update one or more MANIFESTs.",
    .positional_args = &.{.init(
        .root,
        []const []const u8,
        .{
            .help = "Root MANIFEST.json or directory.",
            .count = .unlimited,
            .default_value = &.{"."},
        },
    )},
    .named_args = &.{
        .init(.sort, bool, .{
            .help = "Sort the filenames.",
            .default_value = true,
        }),
        .init(.mtime, bool, .{
            .help = "Consider mtime when matching.",
            .default_value = true,
        }),
        .init(.perms, bool, .{
            .help = "Consider permissions when matching.",
            .default_value = true,
        }),
        .init(.use, []const []const u8, .{
            .help = "Additional place to look for matches.",
            .count = .unlimited,
            .default_value = &.{},
            .short = 'u',
        }),
        .init(.@"use-nested", bool, .{
            .help = "Add any nested manifests we find to the search path.",
            .default_value = false,
            .short = 'n',
        }),
        .init(.@"max-nested-depth", ?usize, .{
            .help = "Max directory depth when search for nested manifests.",
            .default_value = null,
        }),
        .init(.snapshot, ?i64, .{
            .help = "Enable partial snapshot every N seconds.",
            .default_value = null,
        }),
    },
};
