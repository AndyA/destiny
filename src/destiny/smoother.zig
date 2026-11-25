const std = @import("std");

pub fn Smoother(T: type, current_weight: T, sample_weight: T) type {
    return struct {
        const Self = @This();
        current: ?T = null,

        pub const empty: Self = .{};

        pub fn update(self: *Self, sample: T) T {
            const next = blk: {
                if (self.current) |current| {
                    const num = current * current_weight + sample * sample_weight;
                    const den = current_weight + sample_weight;
                    break :blk if (@typeInfo(T) == .int) @divTrunc(num, den) else num / den;
                }
                break :blk sample;
            };
            self.current = next;
            return next;
        }
    };
}
