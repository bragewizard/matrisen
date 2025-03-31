const c = @import("clibs");
const geometry = @import("geometry");
const Root = @import("root.zig");
const Core = @import("../core.zig");
const Mat4x4 = geometry.Mat4x4(f32);
const Allocator = descriptorbuilder.Allocator;
const Writer = descriptorbuilder.Writer;
const descriptorbuilder = @import("../descriptorbuilder.zig");
const buffers = @import("../buffers.zig");
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
    
/// Write the texture data before we start rendering
pub fn writeDescriptorsets(self: *Root, core: *Core) void {
    var sizes = [_]Allocator.PoolSizeRatio{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
        .{ .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
    };
    self.descriptorallocator.init(core.device.handle, 10, &sizes, core.cpuallocator);

    self.meshshader.textureset = self.descriptorallocator.allocate(core.device.handle, self.meshshader.texturelayout, null);
    self.shapes.textureset = self.descriptorallocator.allocate(core.device.handle, self.shapes.texturelayout, null);
    self.pbr.textureset = self.descriptorallocator.allocate(core.device.handle, self.pbr.texturelayout, null);

    core.buffers.uniform[0] = buffers.create(
        core,
        @sizeOf(MaterialConstantsUniform),
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    var materialuniformdata = @as(
        *MaterialConstantsUniform,
        @alignCast(@ptrCast(core.buffers.uniform[0].info.pMappedData.?)),
    );
    materialuniformdata.colorfactors = Vec4{ .x = 1, .y = 1, .z = 1, .w = 1 };
    materialuniformdata.metalrough_factors = Vec4{ .x = 1, .y = 0.5, .z = 1, .w = 1 };

    {
        var writer: Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.clear();
        writer.write_buffer(
            0,
            core.buffers.uniform[0].buffer,
            @sizeOf(MaterialConstantsUniform),
            0,
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.write_image(
            1,
            core.images.textures[1].views[0],
            core.images.samplers[0],
            c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        );
        writer.write_image(
            2,
            core.images.textures[1].views[0],
            core.images.samplers[0],
            c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL,
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        );
        writer.update_set(core.device.handle, self.meshshader.textureset);
        writer.update_set(core.device.handle, self.pbr.textureset);
        writer.update_set(core.device.handle, self.shapes.textureset);
    }
}
