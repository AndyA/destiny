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
const Smoother = @import("../destiny/smoother.zig").Smoother;
const tools = @import("../destiny/tools.zig");

const MANIFEST = "MANIFEST.json";
const SNAPSHOT = "MANIFEST.SNAPSHOT.json";
const MAX_SNAPSHOT_TIME_DENOMINATOR = 20;

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
    Io.File.ReadStreamingError ||
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

        const sha256 = try tools.sha256File(self.io, file);
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
    var smoother: Smoother(@FieldType(std.Io.Timestamp, "nanoseconds"), 15, 1) = .empty;

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
            const delay: Io.Duration = blk: {
                const base: Io.Duration = .fromSeconds(snap);
                if (smoother.current) |current| {
                    if (current * MAX_SNAPSHOT_TIME_DENOMINATOR > base.nanoseconds)
                        break :blk .fromNanoseconds(current * MAX_SNAPSHOT_TIME_DENOMINATOR);
                }
                break :blk base;
            };
            const deadline = snapshot_time.addDuration(delay);
            const start_time: std.Io.Timestamp = .now(self.io, .awake);
            if (start_time.nanoseconds >= deadline.nanoseconds) {
                try manifest.save(self.io, dir, SNAPSHOT);
                const end_time: std.Io.Timestamp = .now(self.io, .awake);
                _ = smoother.update(end_time.nanoseconds - start_time.nanoseconds);
                snapshot_time = end_time;
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
        .{ .max_depth = args.@"search-depth" },
    );
    defer iter.deinit();

    while (try iter.next()) |item| {
        switch (item.entry.kind) {
            .file => {
                const elt: Pathnames.PathElement = self.pathnames.get(item.entry.path);
                const name = self.pathnames.int.get(elt.name);
                if (isManifest(name)) {
                    std.log.info("Adding \"{f}\" to search path", .{self.fmtPath(item.entry.path)});
                    try self.addToSearch(item.dir, name, elt.parent);
                }
            },
            else => {},
        }
    }
}

pub fn scan(self: *Self, root: []const u8) Error!void {
    const dir: Io.Dir = blk: {
        if (std.fs.path.isAbsolute(root))
            break :blk try Io.Dir.openDirAbsolute(self.io, root, openOptions);
        break :blk try Io.Dir.cwd().openDir(self.io, root, openOptions);
    };
    defer dir.close(self.io);

    try self.scanNestedManifests(dir);

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
        .init(.@"search-depth", usize, .{
            .help = "Max directory depth when searching for existing manifests.",
            .default_value = 1,
        }),
        .init(.snapshot, ?i64, .{
            .help = "Enable snapshot every N seconds.",
            .default_value = null,
        }),
    },
};
