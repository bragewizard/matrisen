const std = @import("std");
const log = std.log.scoped(.commands);
const c = @import("../clibs.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;

pub fn graphics_cmd_pool_info(physical_device: PhysicalDevice) c.VkCommandPoolCreateInfo { // does support compute aswell
    return c.VkCommandPoolCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = physical_device.graphics_queue_family,
    };
}

pub fn graphics_cmdbuffer_info(pool: c.VkCommandPool) c.VkCommandBufferAllocateInfo {
    return c.VkCommandBufferAllocateInfo {
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
}

pub fn transition_image(cmd: c.VkCommandBuffer, image: c.VkImage, current_layout: c.VkImageLayout, new_layout: c.VkImageLayout) void {
    var barrier = std.mem.zeroInit(c.VkImageMemoryBarrier2, .{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2 });
    barrier.srcStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    barrier.srcAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT;
    barrier.dstStageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    barrier.dstAccessMask = c.VK_ACCESS_2_MEMORY_WRITE_BIT | c.VK_ACCESS_2_MEMORY_READ_BIT;
    barrier.oldLayout = current_layout;
    barrier.newLayout = new_layout;

    const aspect_mask: u32 = if (new_layout == c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL) c.VK_IMAGE_ASPECT_DEPTH_BIT else c.VK_IMAGE_ASPECT_COLOR_BIT;
    const subresource_range = std.mem.zeroInit(c.VkImageSubresourceRange, .{
        .aspectMask = aspect_mask,
        .baseMipLevel = 0,
        .levelCount = c.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = c.VK_REMAINING_ARRAY_LAYERS,
    });

    barrier.image = image;
    barrier.subresourceRange = subresource_range;

    const dep_info = std.mem.zeroInit(c.VkDependencyInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO_KHR,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrier,
    });

    c.vkCmdPipelineBarrier2(cmd, &dep_info);
}

pub fn copy_image_to_image(cmd: c.VkCommandBuffer, src: c.VkImage, dst: c.VkImage, src_size: c.VkExtent2D, dst_size: c.VkExtent2D) void {
    var blit_region = c.VkImageBlit2{ .sType = c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2, .pNext = null };
    blit_region.srcOffsets[1].x = @intCast(src_size.width);
    blit_region.srcOffsets[1].y = @intCast(src_size.height);
    blit_region.srcOffsets[1].z = 1;
    blit_region.dstOffsets[1].x = @intCast(dst_size.width);
    blit_region.dstOffsets[1].y = @intCast(dst_size.height);
    blit_region.dstOffsets[1].z = 1;
    blit_region.srcSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blit_region.srcSubresource.baseArrayLayer = 0;
    blit_region.srcSubresource.layerCount = 1;
    blit_region.srcSubresource.mipLevel = 0;
    blit_region.dstSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    blit_region.dstSubresource.baseArrayLayer = 0;
    blit_region.dstSubresource.layerCount = 1;
    blit_region.dstSubresource.mipLevel = 0;

    var blit_info = c.VkBlitImageInfo2{ .sType = c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2, .pNext = null };
    blit_info.srcImage = src;
    blit_info.srcImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    blit_info.dstImage = dst;
    blit_info.dstImageLayout = c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    blit_info.regionCount = 1;
    blit_info.pRegions = &blit_region;
    blit_info.filter = c.VK_FILTER_NEAREST;

    c.vkCmdBlitImage2(cmd, &blit_info);
}
