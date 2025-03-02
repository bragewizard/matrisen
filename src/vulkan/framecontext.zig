const graphics_cmd_pool_info = @import("commands.zig").graphics_cmd_pool_info;
const graphics_cmdbuffer_info = @import("commands.zig").graphics_cmdbuffer_info;
const debug = @import("debug.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;
const descriptors = @import("descriptors.zig");
const vk_alloc_cbs = @import("core.zig").vkallocationcallbacks;
const c = @import("../clibs.zig");
const log = @import("std").log.scoped(.framecontext);

const FRAMES = 2;

const Self = @This();

frames:[FRAMES]FrameContext = .{FrameContext{}} ** FRAMES,
current:usize = 0,

pub const FrameContext = struct {
    swapchain_semaphore: c.VkSemaphore = null,
    render_semaphore: c.VkSemaphore = null,
    render_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    command_buffer: c.VkCommandBuffer = null,
    frame_descriptors : descriptors.Allocator = .{},
};


pub fn init_frames(self: *Self, physical_device: PhysicalDevice, device: c.VkDevice) void {
    const semaphore_ci = c.VkSemaphoreCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    const fence_ci = c.VkFenceCreateInfo {
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    for (&self.frames) |*frame| {
        const command_pool_info = graphics_cmd_pool_info(physical_device);
        debug.check_vk_panic(c.vkCreateCommandPool(device, &command_pool_info, vk_alloc_cbs, &frame.command_pool));
        const command_buffer_info = graphics_cmdbuffer_info(frame.command_pool);
        debug.check_vk_panic(c.vkAllocateCommandBuffers(device, &command_buffer_info, &frame.command_buffer));
        debug.check_vk_panic(c.vkCreateSemaphore(device, &semaphore_ci, vk_alloc_cbs, &frame.swapchain_semaphore));
        debug.check_vk_panic(c.vkCreateSemaphore(device, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore));
        debug.check_vk_panic(c.vkCreateFence(device, &fence_ci, vk_alloc_cbs, &frame.render_fence));
        
        log.info("Created framecontext", .{});
    }    
}

pub fn deinit(self: *Self, device: c.VkDevice) void {
    for (&self.frames) |*frame| {
        c.vkDestroyCommandPool(device, frame.command_pool , vk_alloc_cbs);
        c.vkDestroyFence(device, frame.render_fence, vk_alloc_cbs);
        c.vkDestroySemaphore(device, frame.render_semaphore, vk_alloc_cbs);
        c.vkDestroySemaphore(device, frame.swapchain_semaphore, vk_alloc_cbs);
        frame.frame_descriptors.deinit(device);
    }    
}

pub fn switch_frame(self: *Self) void {
    self.current = (self.current + 1) % FRAMES;
}
