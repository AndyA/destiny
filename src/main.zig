const std = @import("std");
const cli = @import("cli");

const Io = std.Io;
const assert = std.debug.assert;
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Interned = @import("destiny/Interned.zig");
const Pathnames = @import("destiny/Pathnames.zig");

const command_handlers = .{
    .scan = @import("commands/Scan.zig"),
    .link = @import("commands/Link.zig"),
};

const subcommands = blk: {
    const info = @typeInfo(@TypeOf(command_handlers)).@"struct";
    const len = info.field_names.len;
    var subs: [len]cli.Command = undefined;
    for (info.field_names, &subs) |name, *slot| {
        const command = @field(command_handlers, name).command;
        assert(std.mem.eql(u8, @tagName(command.name), name));
        slot.* = command;
    }
    break :blk subs;
};

const destiny_command: cli.Command = .{
    .name = .destiny,
    .subcommands = &subcommands,
};

pub fn main(init: std.process.Init) !void {
    const parsed = try cli.parseAlloc(
        destiny_command,
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
        const info = @typeInfo(@TypeOf(command_handlers)).@"struct";
        const cmd_name = @tagName(subcommand);
        inline for (info.field_names) |field_name| {
            if (std.mem.eql(u8, cmd_name, field_name)) {
                const Command = @field(command_handlers, field_name);
                const args = @field(subcommand, field_name);
                var handler: Command = .init(init.gpa, init.io, &paths, args);
                defer handler.deinit();
                try handler.run();
                break;
            }
        } else unreachable;
    } else {
        std.log.err("No subcommand specified.", .{});
        std.process.exit(1);
    }
}

test {
    std.testing.refAllDecls(@This());
}
