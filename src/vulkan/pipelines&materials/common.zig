const m = @import("../../3Dmath.zig");


pub const ModelPushConstants = extern struct {
    model: m.Mat4,
    vertex_buffer: c.VkDeviceAddress,
};
