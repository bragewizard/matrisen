const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const debug = @import("debug.zig");
const log = std.log.scoped(.asynccontext);
const Core = @import("Core.zig");

const Self = @This();

fence: c.VkFence = null,
command_pool: c.VkCommandPool = null,
command_buffer: c.VkCommandBuffer = null,

pub fn init(self: *Self, core: *Core) void {
    const command_pool_ci: c.VkCommandPoolCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = core.graphics_queue_family,
    };

    const upload_fence_ci: c.VkFenceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };

    debug.check_vk_panic(c.vkCreateFence(
        core.device_handle,
        &upload_fence_ci,
        core.vkallocationcallbacks,
        &self.fence,
    ));
    log.info("Created sync structures", .{});

    debug.check_vk_panic(c.vkCreateCommandPool(
        core.device_handle,
        &command_pool_ci,
        core.vkallocationcallbacks,
        &self.command_pool,
    ));

    const upload_command_buffer_ai: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    debug.check_vk_panic(c.vkAllocateCommandBuffers(
        core.device_handle,
        &upload_command_buffer_ai,
        &self.command_buffer,
    ));
}

pub fn deinit(self: *Self, core: *Core) void {
    c.vkDestroyCommandPool(core.device_handle, self.command_pool, core.vkallocationcallbacks);
    c.vkDestroyFence(core.device_handle, self.fence, core.vkallocationcallbacks);
}

pub fn submitBegin(self: *Self, core: *Core) void {
    debug.check_vk(c.vkResetFences(core.device_handle, 1, &self.fence)) catch {
        @panic("Failed to reset immidiate fence");
    };
    debug.check_vk(c.vkResetCommandBuffer(self.command_buffer, 0)) catch {
        @panic("Failed to reset immidiate command buffer");
    };
    const cmd = self.command_buffer;

    const commmand_begin_ci: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    debug.check_vk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch {
        @panic("Failed to begin command buffer");
    };
}

pub fn submitEnd(self: *Self, core: *Core) void {
    const cmd = self.command_buffer;
    debug.check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

    const cmd_info: c.VkCommandBufferSubmitInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };
    const submit_info: c.VkSubmitInfo2 = .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &cmd_info,
    };
    debug.check_vk_panic(c.vkQueueSubmit2(core.graphics_queue, 1, &submit_info, self.fence));
    debug.check_vk_panic(c.vkWaitForFences(core.device_handle, 1, &self.fence, c.VK_TRUE, 1_000_000_000));
}
