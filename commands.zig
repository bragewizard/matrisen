

fn init_commands(self: *Self) void {
    const command_pool_ci = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = self.graphics_queue_family,
    });

    for (&self.frames) |*frame| {
        check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &frame.command_pool)) catch log.err("Failed to create command pool", .{});

        const command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = frame.command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        });

        check_vk(c.vkAllocateCommandBuffers(self.device, &command_buffer_ai, &frame.main_command_buffer)) catch @panic("Failed to allocate command buffer");

        log.info("Created command pool and command buffer", .{});
    }

    check_vk(c.vkCreateCommandPool(self.device, &command_pool_ci, vk_alloc_cbs, &self.immidiate_command_pool)) catch @panic("Failed to create upload command pool");

    const upload_command_buffer_ai = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.immidiate_command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    });
    check_vk(c.vkAllocateCommandBuffers(self.device, &upload_command_buffer_ai, &self.immidiate_command_buffer)) catch @panic("Failed to allocate upload command buffer");
}
