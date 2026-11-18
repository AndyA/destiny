const std = @import("std");
const Io = std.Io;

path: u32,
inode: Io.File.INode,
size: u64,
permissions: Io.File.Permissions,
kind: Io.File.Kind,
mtime: Io.Timestamp,
hash: u256,
