fn create_buffer(self: *Self, alloc_size: usize, usage: c.VkBufferUsageFlags, memory_usage: c.VmaMemoryUsage) t.AllocatedBuffer {
    const buffer_info = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    });

    const vma_alloc_info = std.mem.zeroInit(c.VmaAllocationCreateInfo, .{
        .usage = memory_usage,
        .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    });

    var new_buffer: t.AllocatedBuffer = undefined;
    check_vk(c.vmaCreateBuffer(self.gpu_allocator, &buffer_info, &vma_alloc_info, &new_buffer.buffer, &new_buffer.allocation, &new_buffer.info)) catch @panic("Failed to create buffer");
    return new_buffer;
}

pub fn upload_mesh(self: *Self, indices: []u32, vertices: []t.Vertex) t.GPUMeshBuffers {
    const index_buffer_size = @sizeOf(u32) * indices.len;
    const vertex_buffer_size = @sizeOf(t.Vertex) * vertices.len;

    var new_surface: t.GPUMeshBuffers = undefined;
    new_surface.vertex_buffer = self.create_buffer(vertex_buffer_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT, c.VMA_MEMORY_USAGE_GPU_ONLY);

    const device_address_info = std.mem.zeroInit(c.VkBufferDeviceAddressInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = new_surface.vertex_buffer.buffer,
    });

    new_surface.vertex_buffer_adress = c.vkGetBufferDeviceAddress(self.device, &device_address_info);
    new_surface.index_buffer = self.create_buffer(index_buffer_size, c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, c.VMA_MEMORY_USAGE_GPU_ONLY);

    const staging = self.create_buffer(index_buffer_size + vertex_buffer_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, c.VMA_MEMORY_USAGE_CPU_ONLY);
    defer c.vmaDestroyBuffer(self.gpu_allocator, staging.buffer, staging.allocation);

    const data: *anyopaque = staging.info.pMappedData.?;

    const byte_data = @as([*]u8, @ptrCast(data));
    @memcpy(byte_data[0..vertex_buffer_size], std.mem.sliceAsBytes(vertices));
    @memcpy(byte_data[vertex_buffer_size..], std.mem.sliceAsBytes(indices));
    const submit_ctx = struct {
        vertex_buffer: c.VkBuffer,
        index_buffer: c.VkBuffer,
        staging_buffer: c.VkBuffer,
        vertex_buffer_size: usize,
        index_buffer_size: usize,
        fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
            const vertex_copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .srcOffset = 0,
                .dstOffset = 0,
                .size = sself.vertex_buffer_size,
            });

            const index_copy_region = std.mem.zeroInit(c.VkBufferCopy, .{
                .srcOffset = sself.vertex_buffer_size,
                .dstOffset = 0,
                .size = sself.index_buffer_size,
            });

            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.vertex_buffer, 1, &vertex_copy_region);
            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.index_buffer, 1, &index_copy_region);
        }
    }{
        .vertex_buffer = new_surface.vertex_buffer.buffer,
        .index_buffer = new_surface.index_buffer.buffer,
        .staging_buffer = staging.buffer,
        .vertex_buffer_size = vertex_buffer_size,
        .index_buffer_size = index_buffer_size,
    };
    self.async_submit(submit_ctx);
    return new_surface;
}
