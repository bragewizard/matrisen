const c = @import("../clibs.zig");
const Core = @import("core.zig");
const debug = @import("debug.zig");
const Device = @import("device.zig").Device;
const log = @import("std").log.scoped(.offframecontext);

const Self = @This();

fence: c.VkFence = null,
command_pool: c.VkCommandPool = null,
command_buffer: c.VkCommandBuffer = null,

pub fn init(self : *Self, core : *Core) void {

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

pub fn deinit(self: *Self, device: c.VkDevice) void {
    c.vkDestroyCommandPool(device, self.command_pool , Core.vkallocationcallbacks);
    c.vkDestroyFence(device, self.fence, Core.vkallocationcallbacks);
}

pub fn submit(self: *@This(), submit_ctx: anytype) void {
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
    debug.check_vk(c.vkResetFences(self.device, 1, &self.fence)) catch @panic("Failed to reset immidiate fence");
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

    debug.check_vk(c.vkQueueSubmit2(self.graphics_queue, 1, &submit_info, self.fence)) catch @panic("Failed to submit to graphics queue");
    debug.check_vk(c.vkWaitForFences(self.device, 1, &self.fence, c.VK_TRUE, 1_000_000_000)) catch @panic("Failed to wait for immidiate fence");
}
