const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const assert = std.debug.assert;

const Smoother = @import("destiny/smoother.zig").Smoother;

pub fn main(init: std.process.Init) !void {
    _ = init;
    var smoo: Smoother(u64, 15, 1) = .empty;
    for (0..10) |i| {
        print("{d:>3}: {d:>8}\n", .{ i, smoo.update(if (i == 0) 0 else 100_000) });
    }
}

test {
    std.testing.refAllDecls(@This());
}
