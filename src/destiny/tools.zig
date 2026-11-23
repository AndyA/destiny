const std = @import("std");
const Io = std.Io;

pub fn sha256File(io: Io, file: Io.File) Io.File.ReadStreamingError!u256 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [128 * 1024]u8 = undefined;

    read: while (true) {
        const n_read = file.readStreaming(io, &.{&buf}) catch |err| {
            switch (err) {
                error.EndOfStream => break :read,
                else => return err,
            }
        };
        hasher.update(buf[0..n_read]);
    }

    const hash = hasher.finalResult();
    return std.mem.readInt(u256, &hash, .big);
}
