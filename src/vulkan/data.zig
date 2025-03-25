const Core = @import("core.zig");
const gltf = @import("gltf.zig");
const c = @import("clibs");
const Vec4 = @import("linalg").Vec4(f32);
const debug = @import("debug.zig");
const image = @import("image.zig");
const metalrough = @import("pipelines/metallicroughness.zig");
const descriptors = @import("descriptor.zig");
const common = @import("pipelines/common.zig");
const std = @import("std");
const buffer = @import("buffer.zig");

pub fn init_default(core: *Core) void {
    core.meshassets = gltf.load_meshes(core, "assets/suzanne.glb") catch @panic("Failed to load mesh");
    const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
    var white: u32 = Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
    var grey: u32 = Vec4.packU8(.{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 });
    var black: u32 = Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 0 });
    const magenta: u32 = Vec4.packU8(.{ .x = 1, .y = 0, .z = 1, .w = 1 });

    core.allocatedimages[2] = image.create_upload(
        core,
        &white,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    core.allocatedimages[3] = image.create_upload(
        core,
        &grey,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    core.allocatedimages[4] = image.create_upload(
        core,
        &black,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    core.imageviews[2] = image.create_view(
        core.device.handle,
        core.allocatedimages[3].image,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        1,
    );

    var checker = [_]u32{0} ** (16 * 16);
    for (0..16) |x| {
        for (0..16) |y| {
            const tile = ((x % 2) ^ (y % 2));
            checker[y * 16 + x] = if (tile == 1) black else magenta;
        }
    }
    core.allocatedimages[5] = image.create_upload(
        core,
        &checker,
        .{ .width = 16, .height = 16, .depth = 1 },
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );

    var sampl = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_NEAREST,
        .minFilter = c.VK_FILTER_NEAREST,
    };

    debug.check_vk(
        c.vkCreateSampler(core.device.handle, &sampl, null, &core.samplers[0]),
    ) catch @panic("falied to make sampler");
    sampl.magFilter = c.VK_FILTER_LINEAR;
    sampl.minFilter = c.VK_FILTER_LINEAR;
    debug.check_vk(
        c.vkCreateSampler(core.device.handle, &sampl, null, &core.samplers[1]),
    ) catch @panic("failed to make sampler");

    var materialresources = metalrough.MaterialResources{};
    materialresources.colorimageview = core.imageviews[2];
    materialresources.colorsampler = core.samplers[0];
    materialresources.metalroughimageview = core.imageviews[2];
    materialresources.metalroughsampler = core.samplers[0];

    core.allocatedbuffers[0] = buffer.create(
        core,
        @sizeOf(metalrough.MaterialConstantsUniform),
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    var sceneuniformdata = @as(
        *metalrough.MaterialConstantsUniform,
        @alignCast(@ptrCast(core.allocatedbuffers[0].info.pMappedData.?)),
    );
    sceneuniformdata.colorfactors = Vec4{ .x = 1, .y = 1, .z = 1, .w = 1 };
    sceneuniformdata.metalrough_factors = Vec4{ .x = 1, .y = 0.5, .z = 1, .w = 1 };
    materialresources.databuffer = core.allocatedbuffers[0].buffer;
    materialresources.databuffer_offset = 0;

    core.descriptorsets[1] = core.globaldescriptorallocator.allocate(
        core.device.handle,
        core.descriptorsetlayouts[3],
        null,
    );
    core.descriptorsets[2] = core.globaldescriptorallocator.allocate(
        core.device.handle,
        core.descriptorsetlayouts[5],
        null,
    );
    {
        var writer: descriptors.Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.clear();
        writer.write_buffer(
            0,
            materialresources.databuffer,
            @sizeOf(metalrough.MaterialConstantsUniform),
            materialresources.databuffer_offset,
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.write_image(
            1,
            materialresources.colorimageview,
            materialresources.colorsampler,
            c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        );
        writer.write_image(
            2,
            materialresources.metalroughimageview,
            materialresources.metalroughsampler,
            c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        );
        writer.update_set(core.device.handle, core.descriptorsets[1]);
        writer.update_set(core.device.handle, core.descriptorsets[2]);
    }
    std.log.info("Initialized default data", .{});
}
