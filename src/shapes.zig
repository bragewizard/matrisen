pub const Line = extern struct {
    p0: [3]f32,
    p1: [3]f32,

    pub fn new(p0: [3]f32, p1: [3]f32) Line {
        return .{
            .p0 = .{ p0[0], p0[1], p0[2] },
            .p1 = .{ p1[0], p1[1], p1[2] },
        };
    }
};
