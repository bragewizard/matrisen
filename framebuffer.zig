pub const FrameData = struct {
    swapchain_semaphore: c.VkSemaphore = null,
    render_semaphore: c.VkSemaphore = null,
    render_fence: c.VkFence = null,
    command_pool: c.VkCommandPool = null,
    main_command_buffer: c.VkCommandBuffer = null,
    frame_descriptors: DescriptorAllocatorGrowable = DescriptorAllocatorGrowable{},
};
