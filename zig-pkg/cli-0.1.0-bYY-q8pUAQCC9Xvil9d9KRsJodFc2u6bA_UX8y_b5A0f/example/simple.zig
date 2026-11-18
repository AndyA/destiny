// The helptext looks like this:
//
// Usage: /home/jeff/repos/cli/zig-out/bin/simple [OPTIONS] <message>

// Make a cow speak.

// POSITIONAL ARGUMENTS
//   message
//     Message said by the cow.

// OPTIONS
//   -h, --help
//     Print this help and exit.

//   --red, --no-red
//     Change text color to red.
//     Default: false

const std = @import("std");
const cli = @import("cli");

pub const command: cli.Command = .{
    .name = .cowsay,
    .positional_args = &.{
        .init(.message, [:0]const u8, .{ .help = "Message said by the cow." }),
    },
    .named_args = &.{
        .init(.red, bool, .{ .help = "Change text color to red.", .default_value = false }),
    },
    .help = "Make a cow speak.\n",
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const parsed = try cli.parse(
        command,
        try init.minimal.args.toSlice(init.arena.allocator()),
        .{
            .exit_usage_error = true,
            .render_usage_errors = true,
            .exit_help = true,
            .render_help = .{ .generated = io },
        },
    );

    var buf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &buf);
    const out = &stdout.interface;

    if (parsed.kind.args.red) {
        try out.writeAll("\x1b[31m");
    }

    try out.writeByte('\n');
    for (0..parsed.kind.args.message.len + 4) |_| {
        try out.writeByte('+');
    }
    try out.print("\n+ {s} +\n", .{parsed.kind.args.message});
    for (0..parsed.kind.args.message.len + 4) |_| {
        try out.writeByte('+');
    }
    try out.writeByte('\n');

    const cow =
        \\            \   ^__^
        \\            \  (oo)\_______
        \\                (__)\       )\/\
        \\                    ||----w |
        \\                    ||     ||
        \\
        \\
    ;
    try out.writeAll(cow);

    if (parsed.kind.args.red) {
        try out.writeAll("\x1b[31m");
    }

    try out.flush();
}
