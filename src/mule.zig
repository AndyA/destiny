const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

const JSON =
    \\{}{}
;

pub fn main(init: std.process.Init) !void {
    var io_reader: Io.Reader = .fixed(JSON);
    var reader: std.json.Scanner.Reader = .init(init.gpa, &io_reader);
    defer reader.deinit();
    print("state: {s}\n", .{@tagName(reader.scanner.state)});

    obj: while (true) {
        const tok = reader.nextAlloc(init.arena.allocator(), .alloc_if_needed) catch |err| switch (err) {
            error.UnexpectedEndOfInput => break :obj,
            else => return err,
        };
        print("token: {any} ({s})\n", .{ tok, @tagName(reader.scanner.state) });
        if (tok == .object_end) {
            reader.scanner.state = .value;
        }
    }
}
