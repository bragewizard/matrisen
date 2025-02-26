const c = @import("../clibs.zig");
const check_vk = @import("debug.zig").check_vk;
const std = @import("std");

pub const AllocatedImage = struct {
    image: c.VkImage,
    allocation: c.VmaAllocation,
};

pub const ImageAndView = struct {
    image: c.VkImage,
    view: c.VkImageView,
};

pub const AllocatedImageAndView = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
};

// fn standard_image(comptime name: []const u8, comptime usage: c.VkImageUsageFlags) c.VkImageCreateInfo {
//     name = c.VkImageCreateInfo {
//         .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
//         .pNext = null,
//         .usage = usage,
//         .imageType = c.VK_IMAGE_TYPE_2D,
//         .format = format,
//         .extent = size,
//         .mipLevels = 1,
//         .arrayLayers = 1,
//         .samples = c.VK_SAMPLE_COUNT_1_BIT,
//         .tiling = c.VK_IMAGE_TILING_OPTIMAL,
//     };
//     return name;
// }

// const standard_view_info = c.VkImageViewCreateInfo {
//     .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
//     .pNext = null,
//     .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
//     .image = new_image.image,
//     .format = format,
//     .subresourceRange = .{
//         .aspectMask = @as(u32, @intCast(aspect_flags)),
//         .baseMipLevel = 0,
//         .levelCount = img_info.mipLevels,
//         .baseArrayLayer = 0,
//         .layerCount = 1,
//     },
// };

const alloc_info = c.VmaAllocationCreateInfo {
    .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
    .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
};

// fn create_image(device: c.VkDevice, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags ) t.AllocatedImageAndView {
//     var new_image: t.AllocatedImageAndView = undefined;

//     const alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
//         .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
//         .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
//     });
//     check_vk(c.vmaCreateImage(self.gpu_allocator, &img_info, &alloc_info, &new_image.image, &new_image.allocation, null)) catch @panic("failed to make image");
//     var aspect_flags = c.VK_IMAGE_ASPECT_COLOR_BIT;
//     if (format == c.VK_FORMAT_D32_SFLOAT) {
//         aspect_flags = c.VK_IMAGE_ASPECT_DEPTH_BIT;
//     }

//     const view_info = std.mem.zeroInit( c.VkImageViewCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
//         .pNext = null,
//         .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
//         .image = new_image.image,
//         .format = format,
//         .subresourceRange = .{
//             .aspectMask = @as(u32, @intCast(aspect_flags)),
//             .baseMipLevel = 0,
//             .levelCount = img_info.mipLevels,
//             .baseArrayLayer = 0,
//             .layerCount = 1,
//         },
//     });

//     check_vk(c.vkCreateImageView(device, &view_info, null, &new_image.view)) catch @panic("failed to make image view");
//     return new_image;
// }

// fn create_upload_image(self: *Self, data: *anyopaque, size: c.VkExtent3D, format: c.VkFormat, usage: c.VkImageUsageFlags, mipmapped: bool) t.AllocatedImageAndView {
//     const data_size = size.width * size.height * size.depth * 4;

//     const staging = self.create_buffer(data_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_TO_GPU);
//     defer c.vmaDestroyBuffer(self.gpu_allocator, staging.buffer, staging.allocation);

//     const byte_data = @as([*]u8, @ptrCast(staging.info.pMappedData.?));
//     const byte_src = @as([*]u8, @ptrCast(data));
//     @memcpy(byte_data[0..data_size], byte_src[0..data_size]);

//     const new_image = self.create_image(size, format, usage | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, mipmapped);
//     const submit_ctx = struct {
//         image: c.VkImage,
//         size: c.VkExtent3D,
//         staging_buffer: c.VkBuffer,
//         fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
//             transition_image(cmd, sself.image, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);
//             const image_copy_region = std.mem.zeroInit(c.VkBufferImageCopy, .{
//                 .bufferOffset = 0,
//                 .bufferRowLength = 0,
//                 .bufferImageHeight = 0,
//                 .imageSubresource = .{
//                     .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
//                     .mipLevel = 0,
//                     .baseArrayLayer = 0,
//                     .layerCount = 1,
//                 },
//                 .imageExtent = sself.size,
//             });
//             c.vkCmdCopyBufferToImage(cmd, sself.staging_buffer, sself.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &image_copy_region);
//             transition_image(cmd, sself.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
//         }
//     }{
//         .image = new_image.image,
//         .size = size,
//         .staging_buffer = staging.buffer,
//     };

//     self.immediate_submit(submit_ctx);
//     return new_image;
// }

// fn destroy_image(self: *Self, img: t.AllocatedImageAndView) void {
//     c.vkDestroyImageView(self.device, img.view, vk_alloc_cbs);
//     c.vmaDestroyImage(self.gpu_allocator, img.image, img.allocation);
// }

pub fn create_image_view(device: c.VkDevice, image: c.VkImage, format: c.VkFormat, aspect_flags: c.VkImageAspectFlags, alloc_cb: ?*c.VkAllocationCallbacks) !c.VkImageView {
    const view_info = c.VkImageViewCreateInfo {
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
