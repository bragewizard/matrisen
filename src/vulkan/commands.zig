const std = @import("std");
const log = std.log.scoped(.commands);
const c = @import("../clibs.zig");
const PhysicalDevice = @import("device.zig").PhysicalDevice;
const buffer = @import("buffer.zig");
const debug = @import("debug.zig");
const Core = @import("core.zig");
const Device = @import("device.zig").Device;
const descriptors = @import("descriptors.zig");
const vk_alloc_cbs = @import("core.zig").vkallocationcallbacks;

const FRAMES = 2;

pub const FrameContexts = struct {
    frames:[FRAMES]Context = .{Context{}} ** FRAMES,
    current:u8 = 0,

    pub const Context = struct {
        swapchain_semaphore: c.VkSemaphore = null,
        render_semaphore: c.VkSemaphore = null,
        render_fence: c.VkFence = null,
        command_pool: c.VkCommandPool = null,
        command_buffer: c.VkCommandBuffer = null,
        descriptors : descriptors.Allocator = .{},
        allocatedbuffers: buffer.AllocatedBuffer = undefined,

        pub fn flush(self: *Context, core: *Core) void {
            c.vmaDestroyBuffer(core.gpuallocator, self.allocatedbuffers.buffer, self.allocatedbuffers.allocation);
        }
    };


    pub fn init_frames(self: *FrameContexts, core: *Core) void {
        const semaphore_ci = c.VkSemaphoreCreateInfo {
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        const fence_ci = c.VkFenceCreateInfo {
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        for (&self.frames) |*frame| {
            const command_pool_info = graphics_cmd_pool_info(core.physicaldevice);
            debug.check_vk_panic(c.vkCreateCommandPool(core.device.handle, &command_pool_info, vk_alloc_cbs, &frame.command_pool));
            const command_buffer_info = graphics_cmdbuffer_info(frame.command_pool);
            debug.check_vk_panic(c.vkAllocateCommandBuffers(core.device.handle, &command_buffer_info, &frame.command_buffer));
            debug.check_vk_panic(c.vkCreateSemaphore(core.device.handle, &semaphore_ci, vk_alloc_cbs, &frame.swapchain_semaphore));
            debug.check_vk_panic(c.vkCreateSemaphore(core.device.handle, &semaphore_ci, vk_alloc_cbs, &frame.render_semaphore));
            debug.check_vk_panic(c.vkCreateFence(core.device.handle, &fence_ci, vk_alloc_cbs, &frame.render_fence));
            log.info("Created framecontext", .{});
        }    
    }

    pub fn deinit(self: *FrameContexts, core: *Core) void {
        for (&self.frames) |*frame| {
            c.vkDestroyCommandPool(core.device.handle, frame.command_pool , vk_alloc_cbs);
            c.vkDestroyFence(core.device.handle, frame.render_fence, vk_alloc_cbs);
            c.vkDestroySemaphore(core.device.handle, frame.render_semaphore, vk_alloc_cbs);
            c.vkDestroySemaphore(core.device.handle, frame.swapchain_semaphore, vk_alloc_cbs);
            frame.descriptors.deinit(core.device.handle);
            frame.flush(core);
        }    
    }

    pub fn switch_frame(self: *FrameContexts) void {
        self.current = (self.current + 1) % FRAMES;
    }
};


pub const OffFrameContext = struct {
    fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    command_buffer: c.VkCommandBuffer = null,

    pub fn init(self : *OffFrameContext, core : *Core) void {

        const command_pool_ci : c.VkCommandPoolCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = core.physicaldevice.graphics_queue_family,
        };
    
        const upload_fence_ci : c.VkFenceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        };

        debug.check_vk(c.vkCreateFence(core.device.handle, &upload_fence_ci, Core.vkallocationcallbacks, &self.fence)) catch @panic("Failed to create upload fence");
        log.info("Created sync structures", .{});

        debug.check_vk(c.vkCreateCommandPool(core.device.handle, &command_pool_ci, Core.vkallocationcallbacks, &self.command_pool)) catch @panic("Failed to create upload command pool");

        const upload_command_buffer_ai : c.VkCommandBufferAllocateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = self.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };
        debug.check_vk(c.vkAllocateCommandBuffers(core.device.handle, &upload_command_buffer_ai, &self.command_buffer)) catch @panic("Failed to allocate upload command buffer");
    }

    pub fn deinit(self: *OffFrameContext, device: c.VkDevice) void {
        c.vkDestroyCommandPool(device, self.command_pool , Core.vkallocationcallbacks);
        c.vkDestroyFence(device, self.fence, Core.vkallocationcallbacks);
    }

    pub fn submit(self: *OffFrameContext, core: *Core, submit_ctx: anytype) void {
        comptime {
            var Context = @TypeOf(submit_ctx);
            var is_ptr = false;
            switch (@typeInfo(Context)) {
                .Struct, .Union, .Enum => {},
                .Pointer => |ptr| {
                    if (ptr.size != .One) {
                        @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a multi element pointer");
                    }
                    Context = ptr.child;
                    is_ptr = true;
                    switch (Context) {
                        .Struct, .Union, .Enum, .Opaque => {},
                        else => @compileError("Context must be a type with a submit function. " ++ @typeName(Context) ++ "is a pointer to a non struct/union/enum/opaque type"),
                    }
                },
                else => @compileError("Context must be a type with a submit method. Cannot use: " ++ @typeName(Context)),
            }

            if (!@hasDecl(Context, "submit")) {
                @compileError("Context should have a submit method");
            }

            const submit_fn_info = @typeInfo(@TypeOf(Context.submit));
            if (submit_fn_info != .Fn) {
                @compileError("Context submit method should be a function");
            }

            if (submit_fn_info.Fn.params.len != 2) {
                @compileError("Context submit method should have two parameters");
            }

            if (submit_fn_info.Fn.params[0].type != Context) {
                @compileError("Context submit method first parameter should be of type: " ++ @typeName(Context));
            }

            if (submit_fn_info.Fn.params[1].type != c.VkCommandBuffer) {
                @compileError("Context submit method second parameter should be of type: " ++ @typeName(c.VkCommandBuffer));
            }
        }
        debug.check_vk(c.vkResetFences(core.device.handle, 1, &self.fence)) catch @panic("Failed to reset immidiate fence");
        debug.check_vk(c.vkResetCommandBuffer(self.command_buffer, 0)) catch @panic("Failed to reset immidiate command buffer");
        const cmd = self.command_buffer;

        const commmand_begin_ci : c.VkCommandBufferBeginInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        debug.check_vk(c.vkBeginCommandBuffer(cmd, &commmand_begin_ci)) catch @panic("Failed to begin command buffer");

        submit_ctx.submit(cmd);

        debug.check_vk(c.vkEndCommandBuffer(cmd)) catch @panic("Failed to end command buffer");

        const cmd_info : c.VkCommandBufferSubmitInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = cmd,
        };
        const submit_info : c.VkSubmitInfo2 = .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmd_info,
        };

        debug.check_vk(c.vkQueueSubmit2(core.device.graphics_queue, 1, &submit_info, self.fence)) catch @panic("Failed to submit to graphics queue");
        debug.check_vk(c.vkWaitForFences(core.device.handle, 1, &self.fence, c.VK_TRUE, 1_000_000_000)) catch @panic("Failed to wait for immidiate fence");
    }
};

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
