const c = @import("../clibs.zig");
const Core = @import("core.zig");
const check_vk = @import("debug.zig").check_vk;
const buffer = @import("buffer.zig");
const commands = @import("commands.zig");
const std = @import("std");
const log = std.log.scoped(.images);

pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
};

pub fn create(core: *Core, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags) AllocatedImage {
    var new_image: AllocatedImage = undefined;
    const img_info = c.VkImageCreateInfo{
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

    const alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });
    check_vk(c.vmaCreateImage(core.gpuallocator, &img_info, &alloc_info, &new_image.image, &new_image.allocation, null)) catch @panic("failed to make image");
    var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (format == c.VK_FORMAT_D32_SFLOAT) {
        aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
    }

    return new_image;
}

pub fn create_view(device: c.VkDevice, image: c.VkImage, format: c.VkFormat, aspect_flags: c.VkImageAspectFlags, alloc_cb: ?*c.VkAllocationCallbacks) !c.VkImageView {
    const view_info = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{ .r = c.VK_COMPONENT_SWIZZLE_IDENTITY, .g = c.VK_COMPONENT_SWIZZLE_IDENTITY, .b = c.VK_COMPONENT_SWIZZLE_IDENTITY, .a = c.VK_COMPONENT_SWIZZLE_IDENTITY },
        .subresourceRange = .{
            .aspectMask = aspect_flags,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var image_view: c.VkImageView = undefined;
    try check_vk(c.vkCreateImageView(device, &view_info, alloc_cb, &image_view));
    return image_view;
}

pub fn create_upload(core: *Core, data: *anyopaque, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags, mipmapped: bool) AllocatedImage {
    const data_size = size.width * size.height * size.depth * 4;

    const staging = buffer.create(core, data_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    defer c.vmaDestroyBuffer(core.gpuallocator, staging.buffer, staging.allocation);

    const byte_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
    const byte_src = @as([*]u8, @ptrCast(data));
    @memcpy(byte_data[0..data_size], byte_src[0..data_size]);

    const new_image = create(size, format, usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, mipmapped);
    const submit_ctx = struct {
        image: c.VkImage,
        size: c.VkExtent3D,
        staging_buffer: c.VkBuffer,
        fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
            commands.transition_image(cmd, sself.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
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
                .imageExtent = sself.size,
            });
            c.vkCmdCopyBufferToImage(cmd, sself.staging_buffer, sself.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &image_copy_region);
            commands.transition_image(cmd, sself.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
        }
    }{
        .image = new_image.image,
        .size = size,
        .staging_buffer = staging.buffer,
    };

    core.off_framecontext.submit(submit_ctx);
    return new_image;
}

pub fn create_draw_and_depth_image(core: *Core) void {
    const extent: c.VkExtent3D = .{
        .width = core.extents2d[0].width,
        .height = core.extents2d[0].height,
        .depth = 1,
    };

    const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
    const draw_image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_STORAGE_BIT,
    };

    const draw_image_ai = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    });

    check_vk(c.vmaCreateImage(core.gpuallocator, &draw_image_ci, &draw_image_ai, &core.allocatedimages[0].image, &core.allocatedimages[0].allocation, null)) catch @panic("Failed to create draw image");
    const draw_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = core.allocatedimages[0].image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });

    check_vk(c.vkCreateImageView(core.device.handle, &draw_image_view_ci, Core.vkallocationcallbacks, &core.imageviews[0])) catch @panic("Failed to create draw image view");

    const depth_extent = extent;
    const depth_format = c.VK_FORMAT_D32_SFLOAT;
    const depth_image_ci : c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = depth_format,
        .extent = depth_extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
    };

    check_vk(c.vmaCreateImage(core.gpuallocator, &depth_image_ci, &draw_image_ai, &core.allocatedimages[1].image, &core.allocatedimages[1].allocation, null)) catch @panic("Failed to create depth image");

    const depth_image_view_ci = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = core.allocatedimages[1].image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = depth_format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    });
    check_vk(c.vkCreateImageView(core.device.handle, &depth_image_view_ci, Core.vkallocationcallbacks, &core.imageviews[1])) catch @panic("Failed to create depth image view");
    log.info("Created depth and draw image", .{});
}
