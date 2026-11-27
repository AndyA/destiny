const std = @import("std");
const cli = @import("cli");

const Io = std.Io;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const K = @import("../destiny/constants.zig");
const Pathnames = @import("../destiny/Pathnames.zig");
const Manifest = @import("../destiny/Manifest.zig");

const Self = @This();
const Args = cli.Parsed(command);

allocator: Allocator,
io: Io,
pathnames: *Pathnames,
args: Args,

pub fn init(allocator: Allocator, io: Io, pathnames: *Pathnames, args: Args) Self {
    return .{
        .allocator = allocator,
        .io = io,
        .pathnames = pathnames,
        .args = args,
    };
}

pub fn deinit(_: *Self) void {}

pub fn run(self: *Self) !void {
    _ = self;
}

pub const command: cli.Command = .{
    .name = .link,
    .help = "Hard link files that have the same contents.\n" ++
        "When multiple directories / manifests are specified link each individually.",
    .help_short = "Hard link files that have the same contents.",
    .positional_args = &.{.init(
        .root,
        []const []const u8,
        .{
            .help = "Root " ++ K.MANIFEST ++ " or directory.",
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
