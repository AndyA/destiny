const std = @import("std");
const cli = @import("cli");

const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");

test {
    _ = @import("destiny/Interned.zig");
    _ = @import("destiny/Pathnames.zig");
    _ = @import("destiny/PathIndexer.zig");
    _ = @import("destiny/PathWriter.zig");
    _ = @import("destiny/Manifest.zig");
    _ = @import("destiny/file_iterator.zig");
}

const command_handlers = .{
    .scan = @import("commands/Scan.zig"),
    // .link = @import("commands/Link.zig"),
};

const subcommands = blk: {
    const info = @typeInfo(@TypeOf(command_handlers)).@"struct";
    const len = info.field_names.len;
    var subs: [len]cli.Command = undefined;
    for (info.field_names, &subs) |name, *slot| {
        slot.* = @field(command_handlers, name).command;
    }
    break :blk subs;
};

const command: cli.Command = .{
    .name = .destiny,
    .subcommands = &subcommands,
};

pub fn main(init: std.process.Init) !void {
    const parsed = try cli.parseAlloc(
        command,
        init.arena.allocator(),
        try init.minimal.args.toSlice(init.arena.allocator()),
        .{
            .exit_usage_error = true,
            .render_usage_errors = true,
            .exit_help = true,
            .render_help = .{ .generated = init.io },
        },
    );

    var int: Interned = try .init(init.gpa);
    defer int.deinit();
    var paths: Pathnames = try .init(init.gpa, &int);
    defer paths.deinit();

    if (parsed.subcommand) |subcommand| {
        print("subcommand: {s}\n", .{@tagName(subcommand)});
        switch (subcommand) {
            inline else => |args| {
                const info = @typeInfo(@TypeOf(command_handlers)).@"struct";
                const Command = @field(command_handlers, info.field_names[@backingInt(subcommand)]);

                var handler: Command = .init(init.gpa, init.io, &paths, args);
                defer handler.deinit();
                try handler.run();
            },
        }
    } else {
        std.log.err("No subcommand specified.", .{});
        std.process.exit(1);
    }
}
