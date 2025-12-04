const c = @import("../clibs/clibs.zig").libs;
const std = @import("std");
const debug = @import("debug.zig");
const log = std.log.scoped(.framecontext);
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const PhysicalDevice = @import("PhysicalDevice.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");
const transitionImage = @import("Renderer.zig").transitionImage;
const copyImageToImage = @import("Renderer.zig").copyImageToImage;

const Self = @This();

swapchain_semaphore: c.VkSemaphore = null,
render_semaphore: c.VkSemaphore = null,
render_fence: c.VkFence = null,
command_pool: c.VkCommandPool = null,
command_buffer: c.VkCommandBuffer = null,
swapchain_image_index: u32 = 0,
descriptorallocator: DescriptorAllocator = .{},
dynamicset: c.VkDescriptorSet = undefined,

pub fn init(
    self: *Self,
    device: Device,
    physicaldevice: PhysicalDevice,
    allocationcallbacks: ?*c.VkAllocationCallbacks,
) void {
    const semaphore_ci = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    const fence_ci = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    const command_pool_info = graphics_cmd_pool_info(physicaldevice.graphics_queue_family);
    debug.checkVkPanic(c.vkCreateCommandPool(
        device.handle,
        &command_pool_info,
        allocationcallbacks,
        &self.command_pool,
    ));
    const command_buffer_info = graphics_cmdbuffer_info(self.command_pool);
    debug.checkVkPanic(c.vkAllocateCommandBuffers(
        device.handle,
        &command_buffer_info,
        &self.command_buffer,
    ));
    debug.checkVkPanic(c.vkCreateSemaphore(
        device.handle,
        &semaphore_ci,
        allocationcallbacks,
        &self.swapchain_semaphore,
    ));
    debug.checkVkPanic(c.vkCreateSemaphore(
        device.handle,
        &semaphore_ci,
        allocationcallbacks,
        &self.render_semaphore,
    ));
    debug.checkVkPanic(c.vkCreateFence(
        device.handle,
        &fence_ci,
        allocationcallbacks,
        &self.render_fence,
    ));
}

pub fn deinit(self: *Self, device: Device, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyCommandPool(device.handle, self.command_pool, allocationcallbacks);
    c.vkDestroyFence(device.handle, self.render_fence, allocationcallbacks);
    c.vkDestroySemaphore(device.handle, self.render_semaphore, allocationcallbacks);
    c.vkDestroySemaphore(device.handle, self.swapchain_semaphore, allocationcallbacks);
}

pub fn submitBegin(self: *Self, core: *Core) !void {
    const timeout: u64 = 4_000_000_000; // 4 second in nanonesconds
    debug.checkVkPanic(c.vkWaitForFences(core.device.handle, 1, &self.render_fence, c.VK_TRUE, timeout));

    const e = c.vkAcquireNextImageKHR(
        core.device.handle,
        core.swapchain.handle,
        timeout,
        self.swapchain_semaphore,
        null,
        &self.swapchain_image_index,
    );
    if (e == c.VK_ERROR_OUT_OF_DATE_KHR) {
        core.resizerequest = true;
        return error.SwapchainOutOfDate;
    }

    debug.checkVkPanic(c.vkResetFences(core.device.handle, 1, &self.render_fence));
    debug.checkVkPanic(c.vkResetCommandBuffer(self.command_buffer, 0));

    const cmd = self.command_buffer;
    const cmd_begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    debug.checkVkPanic(c.vkBeginCommandBuffer(cmd, &cmd_begin_info));
    const clearvalue = c.VkClearColorValue{ .float32 = .{ 0.014, 0.014, 0.014, 1 } };

    transitionImage(
        cmd,
        core.renderimage.image,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    );

    const color_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = core.drawimage.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .resolveImageView = core.renderimage.view,
        .resolveImageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = c.VK_RESOLVE_MODE_AVERAGE_BIT,
        .clearValue = .{ .color = clearvalue },
    };
    const depth_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = core.depthimage.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = .{ .depthStencil = .{ .depth = 1.0, .stencil = 0.0 } },
    };

    const render_info: c.VkRenderingInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = core.drawextent2d,
        },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = &depth_attachment,
    };

    const viewport: c.VkViewport = .{
        .x = 0.0,
        .y = 0.0,
        .width = @as(f32, @floatFromInt(core.drawextent2d.width)),
        .height = @as(f32, @floatFromInt(core.drawextent2d.height)),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor: c.VkRect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = core.drawextent2d,
    };

    c.vkCmdBeginRendering(cmd, &render_info);
    c.vkCmdSetViewport(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor(cmd, 0, 1, &scissor);
}

pub fn submitEnd(self: *Self, core: *Core) void {
    const cmd = self.command_buffer;
    c.vkCmdEndRendering(cmd);
    transitionImage(
        cmd,
        core.renderimage.image,
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    );
    transitionImage(
        cmd,
        core.swapchain.images[self.swapchain_image_index],
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    );
    copyImageToImage(
        cmd,
        core.renderimage.image,
        core.swapchain.images[self.swapchain_image_index],
        core.drawextent2d,
        core.swapchainextent,
    );
    transitionImage(
        cmd,
        core.swapchain.images[self.swapchain_image_index],
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    );

    debug.checkVkPanic(c.vkEndCommandBuffer(cmd));

    const cmd_info = c.VkCommandBufferSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };

    const wait_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = self.swapchain_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
    };

    const signal_info = c.VkSemaphoreSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = self.render_semaphore,
        .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    };

    const submit = c.VkSubmitInfo2{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &wait_info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal_info,
    };

    debug.checkVkPanic(c.vkQueueSubmit2(core.device.graphics_queue, 1, &submit, self.render_fence));

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &self.render_semaphore,
        .swapchainCount = 1,
        .pSwapchains = &core.swapchain.handle,
        .pImageIndices = &self.swapchain_image_index,
    };
    _ = c.vkQueuePresentKHR(core.device.graphics_queue, &present_info);
    core.framenumber +%= 1;
    core.switch_frame();
}

pub fn graphics_cmd_pool_info(queue_family_index: u32) c.VkCommandPoolCreateInfo {
    return c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_index,
    };
}

pub fn graphics_cmdbuffer_info(pool: c.VkCommandPool) c.VkCommandBufferAllocateInfo {
    return c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
}
