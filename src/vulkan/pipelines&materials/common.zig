const m = @import("../../3Dmath.zig");
const c = @import("../../clibs.zig");

pub const SceneDataUniform = extern struct {
    view: m.Mat4,
    proj: m.Mat4,
    viewproj: m.Mat4,
    ambient_color: m.Vec4,
    sunlight_dir: m.Vec4,
    sunlight_color: m.Vec4,
};

pub const ModelPushConstants = extern struct {
    model: m.Mat4,
    vertex_buffer: c.VkDeviceAddress,
};

pub const MaterialPass = enum {
    MainColor,
    Transparent,
    Other
};

// pub const RenderObject = struct {
//     indexcount : u32,
//     firstindex : u32,
//     indexbuffer : c.VkBuffer,
//     material : *MaterialInstance,
//     transform : m.Mat4,
//     vertex_buffer_address : c.VkDeviceAddress
// };
