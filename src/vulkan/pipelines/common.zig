const linalg = @import("linalg");
const Mat4x4 = linalg.Mat4x4(f32);
const Vec4 = linalg.Vec4(f32);
const c = @import("clibs");

pub const SceneDataUniform = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sunlight_dir: Vec4,
    sunlight_color: Vec4,
};

pub const ModelPushConstants = extern struct {
    model: Mat4x4,
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
