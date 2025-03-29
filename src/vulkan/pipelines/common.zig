const linalg = @import("linalg");
const Core = @import("../core.zig");
const descriptor = @import("../descriptor.zig");
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


pub fn descriptors(core: *Core) void {
    { // scenedata uniform
        var builder: descriptor.LayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        core.descriptorsetlayouts[2] = builder.build(
            core.device.handle,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    { // scenedata uniform for mesh shader
        var builder: descriptor.LayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        core.descriptorsetlayouts[3] = builder.build(
            core.device.handle,
            c.VK_SHADER_STAGE_MESH_BIT_EXT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
}
 
// { // image and sampler, used for per frame swaping of images
//     var builder: LayoutBuilder = .init(core.cpuallocator);
//     defer builder.deinit();
//     builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
//     core.descriptorsetlayouts[1] = builder.build(core.device.handle, c.VK_SHADER_STAGE_FRAGMENT_BIT, null, 0);
// }
