const c = @import("clibs");
const check_vk = @import("debug.zig").check_vk;
const check_vk_panic = @import("debug.zig").check_vk_panic;
const buffer = @import("buffers.zig");
const commands = @import("commands.zig");
const std = @import("std");
const log = std.log.scoped(.images);
const AsyncContext = @import("commands.zig").AsyncContext;
const Vec4 = @import("geometry").Vec4(f32);
const Core = @import("core.zig");


formats: [3]c.VkFormat = undefined,
extent3d: [1]c.VkExtent3D = undefined,
extent2d: [1]c.VkExtent2D = undefined,
allocated: [6]AllocatedImage = undefined,
views: [3]c.VkImageView = undefined,
samplers: [2]c.VkSampler = undefined,

window_extent: c.VkExtent2D = .{},

swapchain_format: c.VkFormat = undefined,
swapchain_extent:c.VkExtent2D = .{},
swapchain: []c.VkImage = &.{},
swapchain_views: []c.VkImageView = &.{},

const Self = @This();

pub fn init(core: *Core) void {
    var self = core.images;
    const extent: c.VkExtent3D = .{
        .width = self.window_extent.width,
        .height = self.window_extent.height,
        .depth = 1,
    };
    self.extent3d[0] = extent;

    const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
    self.formats[1] = format;
    const draw_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT,
    };

    const draw_image_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });

    check_vk_panic(c.vmaCreateImage(
        core.gpuallocator,
        &draw_image_ci,
        &draw_image_ai,
        &self.allocated[0].image,
        &self.allocated[0].allocation,
        null,
    ));
    const draw_image_view_ci : c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.allocated[0].image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
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
        &self.views[0],
    ));

    const depth_extent = extent;
    const depth_format = c.VK_FORMAT_D32_SFLOAT;
    self.formats[2] = depth_format;
    const depth_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = depth_format,
        .extent = depth_extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    };

    check_vk_panic(c.vmaCreateImage(
        core.gpuallocator,
        &depth_image_ci,
        &draw_image_ai,
        &self.allocated[1].image,
        &self.allocated[1].allocation,
        null,
    ));

    const depth_image_view_ci : c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = self.allocated[1].image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = depth_format,
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
        &self.views[1],
    ));
    log.info("Created depth and draw image", .{});

    const size = c.VkExtent3D{ .width = 1, .height = 1, .depth = 1 };
    var white: u32 = Vec4.packU8(.{ .x = 1, .y = 1, .z = 1, .w = 1 });
    var grey: u32 = Vec4.packU8(.{ .x = 0.3, .y = 0.3, .z = 0.3, .w = 1 });
    var black: u32 = Vec4.packU8(.{ .x = 0, .y = 0, .z = 0, .w = 0 });
    const magenta: u32 = Vec4.packU8(.{ .x = 1, .y = 0, .z = 1, .w = 1 });

    self.allocated[2] = create_upload(
        core,
        &white,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    self.allocated[3] = create_upload(
        core,
        &grey,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    self.allocated[4] = create_upload(
        core,
        &black,
        size,
        c.VK_FORMAT_R8G8B8A8_UNORM,
        c.VK_IMAGE_USAGE_SAMPLED_BIT,
        false,
    );
    self.views[2] = create_view(
        core.device.handle,
        self.allocated[3].image,
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
    self.allocated[5] = create_upload(
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
    _ = core;
}



pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
};

pub fn create(core: *Core, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags, mipmapped: bool) AllocatedImage {
    var new_image: AllocatedImage = undefined;
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
    check_vk_panic(c.vmaCreateImage(core.gpuallocator, &img_info, &alloc_info, &new_image.image, &new_image.allocation, null));
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
) AllocatedImage {
    const data_size = size.width * size.height * size.depth * 4;

    const staging = buffer.create(core, data_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
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
    commands.transition_image(cmd, new_image.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
    const image_copy_region = std.mem.zeroInit(c.VkBufferImageCopy, .{
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
    });
    c.vkCmdCopyBufferToImage(cmd, staging.buffer, new_image.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &image_copy_region);
    commands.transition_image(
        cmd,
        new_image.image,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    );
    AsyncContext.submitEnd(core);
    return new_image;
}
