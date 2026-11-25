const std = @import("std");
const cli = @import("cli");

const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("../destiny/Interned.zig");
const Pathnames = @import("../destiny/Pathnames.zig");
const PathWriter = @import("../destiny/PathWriter.zig");
const Manifest = @import("../destiny/Manifest.zig");
const Object = @import("../destiny/Object.zig");
const fi = @import("../destiny/file_iterator.zig");
const sha256File = @import("../destiny/tools.zig").sha256File;

const Self = @This();
const Args = cli.Parsed(command);

pub const openOptions: Io.Dir.OpenOptions = .{
    .follow_symlinks = false,
    .iterate = true,
};

pub const Error = Manifest.AppendError ||
    Manifest.WriteJsonError ||
    Manifest.ReadJsonError ||
    Io.File.StatError ||
    Io.File.OpenError ||
    Io.File.ReadStreamingError ||
    Io.File.Writer.Error ||
    Io.Dir.RenameError;

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

fn createObject(self: *Self, manifest: *Manifest, item: fi.FileIteratorItem) Error!Object {
    if (try manifest.findINode(item.entry.inode)) |found| {
        var object = found;
        object.path = item.entry.path;
        return object;
    }

    const name = self.pathnames.int.get(item.entry.name);
    const file = try item.dir.openFile(self.io, name, .{ .mode = .read_only });
    defer file.close(self.io);

    const stat = try file.stat(self.io);

    const hash = blk: {
        if (try self.matchObject(item.entry.path, stat)) |found|
            break :blk found.hash;

        const sha256 = try sha256File(self.io, file);
        print("  {x:0>64} {f}\n", .{ sha256, self.fmtPath(item.entry.path) });

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

fn saveManifest(self: *const Self, manifest: Manifest, dir: Io.Dir, name: []const u8) Error!void {
    const tmp_name = "tmp.MANIFEST.json";
    const m_file = try dir.createFile(self.io, tmp_name, .{});
    defer m_file.close(self.io);
    var buf: [128 * 1024]u8 = undefined;
    var writer = m_file.writer(self.io, &buf);
    try manifest.writeJson(&writer.interface);
    try writer.flush();
    try dir.rename(tmp_name, dir, name, self.io);
}

fn loadManifestBelow(
    self: *const Self,
    manifest: *Manifest,
    dir: Io.Dir,
    name: []const u8,
    root: Pathnames.Handle,
) Error!void {
    const m_file = try dir.openFile(self.io, name, .{ .mode = .read_only });
    defer m_file.close(self.io);
    var buf: [128 * 1024]u8 = undefined;
    var reader = m_file.reader(self.io, &buf);
    try manifest.readJsonBelow(&reader.interface, root);
}

fn addToSearch(self: *Self, dir: Io.Dir, name: []const u8, root: Pathnames.Handle) Error!void {
    print("Loading {s}\n", .{name});
    var manifest: Manifest = .init(self.allocator, self.pathnames);
    errdefer manifest.deinit();
    try self.loadManifestBelow(&manifest, dir, name, root);
    try self.search.append(self.allocator, manifest);
}

fn maybeAddToSearch(self: *Self, dir: Io.Dir, name: []const u8, root: Pathnames.Handle) Error!void {
    _ = dir.statFile(self.io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    try self.addToSearch(dir, name, root);
}

fn loadManifest(self: *const Self, manifest: *Manifest, dir: Io.Dir, name: []const u8) Error!void {
    try self.loadManifestBelow(manifest, dir, name, Pathnames.ROOT);
}

pub fn scan(self: *Self, root: []const u8) Error!void {
    const dir: Io.Dir = blk: {
        if (std.fs.path.isAbsolute(root))
            break :blk try Io.Dir.openDirAbsolute(self.io, root, openOptions);
        break :blk try Io.Dir.cwd().openDir(self.io, root, openOptions);
    };
    defer dir.close(self.io);

    var manifest: Manifest = .init(self.allocator, self.pathnames);
    defer manifest.deinit();

    try self.maybeAddToSearch(dir, "MANIFEST.json", Pathnames.ROOT);
    try self.maybeAddToSearch(dir, "MANIFEST.PARTIAL.json", Pathnames.ROOT);

    var iter: fi.FileIterator(Self, openOptions) = try .init(
        self.allocator,
        self.io,
        self.pathnames,
        dir,
        self.*,
        .{ .sorted = self.args.kind.args.sort },
    );
    defer iter.deinit();

    while (try iter.next()) |item| {
        switch (item.entry.kind) {
            .file => try manifest.append(try self.createObject(&manifest, item)),
            .directory => print("Scanning {s}/{f}\n", .{ root, self.fmtPath(item.entry.path) }),
            else => |kind| print(
                "  Skipping {s} {f}\n",
                .{ @tagName(kind), self.fmtPath(item.entry.path) },
            ),
        }
    }

    try self.saveManifest(manifest, dir, "MANIFEST.json");
}

pub fn run(self: *Self) !void {
    for (self.args.kind.args.root) |root| {
        print("Scanning {s}\n", .{root});
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
    },
};
