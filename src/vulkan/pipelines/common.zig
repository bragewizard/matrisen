const c = @import("clibs");
const geometry = @import("geometry");
const Mat4x4 = geometry.Mat4x4(f32);
const Vec4 = geometry.Vec4(f32);

pub const MaterialPass = enum { MainColor, Transparent, Other };

pub const ModelPushConstants = extern struct {
    model: Mat4x4,
    vertex_buffer: c.VkDeviceAddress,
};

pub const SceneDataUniform = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sunlight_dir: Vec4,
    sunlight_color: Vec4,
};

pub const MaterialConstantsUniform = extern struct {
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
};

pub const MaterialResources = struct {
    colorimageview: c.VkImageView = undefined,
    colorsampler: c.VkSampler = undefined,
    metalroughimageview: c.VkImageView = undefined,
    metalroughsampler: c.VkSampler = undefined,
    databuffer: c.VkBuffer = undefined,
    databuffer_offset: u32 = undefined,
};
