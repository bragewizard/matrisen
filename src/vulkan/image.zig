const c = @import("clibs").libs;
const check_vk = @import("debug.zig").check_vk;
const check_vk_panic = @import("debug.zig").check_vk_panic;
const buffer = @import("buffers.zig");
const commands = @import("commands.zig");
const std = @import("std");
const log = std.log.scoped(.images);
const AsyncContext = @import("commands.zig").AsyncContext;
const Vec4 = @import("linalg").Vec4(f32);
const Core = @import("core.zig");

textures: [6]AllocatedImage(1) = undefined,
depths: [1]AllocatedImage(1) = undefined,
extent3d: [1]c.VkExtent3D = undefined,
extent2d: [1]c.VkExtent2D = undefined,
samplers: [2]c.VkSampler = undefined,

renderattachmentformat: c.VkFormat = c.VK_FORMAT_R16G16B16A16_SFLOAT,
depth_format: c.VkFormat = c.VK_FORMAT_D32_SFLOAT,
colorattachment: AllocatedImage(1) = undefined,
resolvedattachment: AllocatedImage(1) = undefined,
depthstencilattachment: AllocatedImage(1) = undefined,

swapchain_format: c.VkFormat = undefined,
swapchain_extent: c.VkExtent2D = .{},
swapchain: []c.VkImage = &.{},
swapchain_views: []c.VkImageView = &.{},

const Self = @This();

pub fn AllocatedImage(N: comptime_int) type {
    return struct {
        image: c.VkImage,
        allocation: c.VmaAllocation,
        views: [N]c.VkImageView,
    };
}

pub fn createRenderAttachments(core: *Core) void {
    var self = &core.images;
    const extent: c.VkExtent3D = .{
        .width = self.swapchain_extent.width,
        .height = self.swapchain_extent.height,
        .depth = 1,
    };
    self.extent3d[0] = extent;

    const draw_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.renderattachmentformat,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_4_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
    };

    const draw_image_ai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    check_vk_panic(c.vmaCreateImage(
        core.gpuallocator,
        &draw_image_ci,
        &draw_image_ai,
        &self.colorattachment.image,
        &self.colorattachment.allocation,
        null,
    ));
    const draw_image_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.colorattachment.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.renderattachmentformat,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    check_vk_panic(c.vkCreateImageView(
        core.device.handle,
        &draw_image_view_ci,
        Core.vkallocationcallbacks,
        &self.colorattachment.views[0],
    ));
    const resolved_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.renderattachmentformat,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    };

    const resolved_image_ai: c.VmaAllocationCreateInfo = .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    check_vk_panic(c.vmaCreateImage(
        core.gpuallocator,
        &resolved_image_ci,
        &resolved_image_ai,
        &self.resolvedattachment.image,
        &self.resolvedattachment.allocation,
        null,
    ));
    const resolved_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.resolvedattachment.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.renderattachmentformat,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    check_vk_panic(c.vkCreateImageView(
        core.device.handle,
        &resolved_view_ci,
        Core.vkallocationcallbacks,
        &self.resolvedattachment.views[0],
    ));

    const depth_extent = extent;
    const depth_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = self.depth_format,
        .extent = depth_extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_4_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
    };

    check_vk_panic(c.vmaCreateImage(
        core.gpuallocator,
        &depth_image_ci,
        &draw_image_ai,
        &self.depthstencilattachment.image,
        &self.depthstencilattachment.allocation,
        null,
    ));

    const depth_image_view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.depthstencilattachment.image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = self.depth_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    check_vk_panic(c.vkCreateImageView(
        core.device.handle,
        &depth_image_view_ci,
        Core.vkallocationcallbacks,
        &self.depthstencilattachment.views[0],
    ));
}

pub fn createDefaultTextures(core: *Core) void {
    var self = &core.images;
    const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
    var white: u32 = Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
    var grey: u32 = Vec4.packU8(.{ .x = 0.2, .y = 0.2, .z = 0.2, .w = 1 });
    const grey1 = Vec4.packU8(.{ .x = 0.05, .y = 0.05, .z = 0.05, .w = 1 });
    const grey2 = Vec4.packU8(.{ .x = 0.08, .y = 0.08, .z = 0.08, .w = 1 });
    var black: u32 = Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 1 });

    self.textures[0] = create_upload(
        core,
        &white,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    self.textures[1] = create_upload(
        core,
        &grey,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    self.textures[2] = create_upload(
        core,
        &black,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    self.textures[1].views[0] = create_view(
        core.device.handle,
        self.textures[1].image,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        1,
    );

    var checker = [_]u32{0} ** (16 * 16);
    for (0..16) |x| {
        for (0..16) |y| {
            const tile = ((x % 2) ^ (y % 2));
            checker[y * 16 + x] = if (tile == 1) grey1 else grey2;
        }
    }
    self.textures[3] = create_upload(
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

    check_vk_panic(c.vkCreateSampler(core.device.handle, &sampl, null, &self.samplers[0]));
    sampl.magFilter = c.VK_FILTER_LINEAR;
    sampl.minFilter = c.VK_FILTER_LINEAR;
    check_vk_panic(c.vkCreateSampler(core.device.handle, &sampl, null, &self.samplers[1]));
}

pub fn deinit(core: *Core) void {
    const self = &core.images;
    c.vmaDestroyImage(core.gpuallocator, self.colorattachment.image, self.colorattachment.allocation);
    c.vkDestroyImageView(core.device.handle, self.colorattachment.views[0], null);
    c.vmaDestroyImage(core.gpuallocator, self.resolvedattachment.image, self.resolvedattachment.allocation);
    c.vkDestroyImageView(core.device.handle, self.resolvedattachment.views[0], null);
    c.vmaDestroyImage(core.gpuallocator, self.depthstencilattachment.image, self.depthstencilattachment.allocation);
    c.vkDestroyImageView(core.device.handle, self.depthstencilattachment.views[0], null);
    c.vmaDestroyImage(core.gpuallocator, self.textures[0].image, self.textures[0].allocation);
    // c.vkDestroyImageView(core.device.handle, self.textures[0].views[0], null);
    c.vmaDestroyImage(core.gpuallocator, self.textures[1].image, self.textures[1].allocation);
    c.vkDestroyImageView(core.device.handle, self.textures[1].views[0], null);
    c.vmaDestroyImage(core.gpuallocator, self.textures[2].image, self.textures[2].allocation);
    // c.vkDestroyImageView(core.device.handle, self.textures[2].views[0], null);
    c.vmaDestroyImage(core.gpuallocator, self.textures[3].image, self.textures[3].allocation);
    // c.vkDestroyImageView(core.device.handle, self.textures[3].views[0], null);
    c.vkDestroySampler(core.device.handle, self.samplers[0], null);
    c.vkDestroySampler(core.device.handle, self.samplers[1], null);
    for (self.swapchain_views) |view| {
        c.vkDestroyImageView(core.device.handle, view, null);
    }
    core.cpuallocator.free(self.swapchain);
    core.cpuallocator.free(self.swapchain_views);
}

pub fn create(
    core: *Core,
    size: c.VkExtent3D,
    format: c.VkFormat,
    usage: c.VkImageUsageFlags,
    mipmapped: bool,
) AllocatedImage(1) {
    var new_image: AllocatedImage(1) = undefined;
    var img_info = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .usage = usage,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = size,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
    };

    if (mipmapped) {
        const levels = @floor(std.math.log2(@as(f32, @floatFromInt(@max(size.width, size.height)))) + 1);
        img_info.mipLevels = @intFromFloat(levels);
    }

    const alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });
    check_vk_panic(c.vmaCreateImage(
        core.gpuallocator,
        &img_info,
        &alloc_info,
        &new_image.image,
        &new_image.allocation,
        null,
    ));
    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    return new_image;
}

pub fn create_view(device: c.VkDevice, image: c.VkImage, format: c.VkFormat, miplevels: u32) c.VkImageView {
    var image_view: c.VkImageView = undefined;

    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = .{
            .aspectMask = @intCast(aspect_flags),
            .baseMipLevel = 0,
            .levelCount = miplevels,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    check_vk(c.vkCreateImageView(device, &view_info, null, &image_view)) catch @panic("failed to make image view");
    return image_view;
}

pub fn create_upload(
    core: *Core,
    data: *anyopaque,
    size: c.VkExtent3D,
    format: c.VkFormat,
    usage: c.VkImageUsageFlags,
    mipmapped: bool,
) AllocatedImage(1) {
    const data_size = size.width * size.height * size.depth * 4;

    const staging = buffer.create(
        core,
        data_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    defer c.vmaDestroyBuffer(core.gpuallocator, staging.buffer, staging.allocation);

    const byte_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
    const byte_src = @as([*]u8, @ptrCast(data));
    @memcpy(byte_data[0..data_size], byte_src[0..data_size]);

    const new_image = create(
        core,
        size,
        format,
        usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        mipmapped,
    );
    AsyncContext.submitBegin(core);
    const cmd = core.asynccontext.command_buffer;
    commands.transition_image(
        cmd,
        new_image.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );
    const image_copy_region: c.VkBufferImageCopy = .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageExtent = size,
    };
    c.vkCmdCopyBufferToImage(
        cmd,
        staging.buffer,
        new_image.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &image_copy_region,
    );
    commands.transition_image(
        cmd,
        new_image.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
    AsyncContext.submitEnd(core);
    return new_image;
}
