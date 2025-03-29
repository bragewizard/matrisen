const std = @import("std");
const c = @import("clibs");
const linalg = @import("linalg");
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const debug = @import("debug.zig");
const Core = @import("core.zig");
const commands = @import("commands.zig");
const Self = @This();

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};

pub const Vertex = extern struct {
    position: Vec3,
    uv_x: f32,
    normal: Vec3,
    uv_y: f32,
    color: Vec4,
};

pub const Mesh = struct {
    vertexbuffer: u32,
    indexbuffer: u32,
    vertexbuffer_adress: u32,
};

pub fn create(
    core: *Core,
    alloc_size: usize,
    usage: c.VkBufferUsageFlags,
    memory_usage: c.VmaMemoryUsage,
) AllocatedBuffer {
    const buffer_info: c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = alloc_size,
        .usage = usage,
    };

    const vma_alloc_info: c.VmaAllocationCreateInfo = .{
        .usage = memory_usage,
        .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    };

    var new_buffer: AllocatedBuffer = undefined;
    debug.check_vk(c.vmaCreateBuffer(
        core.gpuallocator,
        &buffer_info,
        &vma_alloc_info,
        &new_buffer.buffer,
        &new_buffer.allocation,
        &new_buffer.info,
    )) catch @panic("Failed to create buffer");
    return new_buffer;
}

pub fn upload_mesh(core: *Core, indices: []u32, vertices: []Vertex) Mesh {
    const index_buffer_size = @sizeOf(u32) * indices.len;
    const vertex_buffer_size = @sizeOf(Vertex) * vertices.len;

    const vertex_buffer = create(
        core,
        vertex_buffer_size,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    const device_address_info: c.VkBufferDeviceAddressInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = vertex_buffer.buffer,
    };

    const index_buffer = create(
        core,
        index_buffer_size,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );


    const staging = create(
        core,
        index_buffer_size + vertex_buffer_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    defer c.vmaDestroyBuffer(core.gpuallocator, staging.buffer, staging.allocation);

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
        pub fn submit(sself: @This(), cmd: c.VkCommandBuffer) void {
            const vertex_copy_region: c.VkBufferCopy = .{
                .srcOffset = 0,
                .dstOffset = 0,
                .size = sself.vertex_buffer_size,
            };

            const index_copy_region: c.VkBufferCopy = .{
                .srcOffset = sself.vertex_buffer_size,
                .dstOffset = 0,
                .size = sself.index_buffer_size,
            };

            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.vertex_buffer, 1, &vertex_copy_region);
            c.vkCmdCopyBuffer(cmd, sself.staging_buffer, sself.index_buffer, 1, &index_copy_region);
        }
    }{
        .vertex_buffer = vertex_buffer.buffer,
        .index_buffer = index_buffer.buffer,
        .staging_buffer = staging.buffer,
        .vertex_buffer_size = vertex_buffer_size,
        .index_buffer_size = index_buffer_size,
    };
    core.asynccontext.submit(core, submit_ctx);
    core.vertex_buffers[0] = vertex_buffer;
    core.index_buffers[0] = index_buffer;
    core.vertex_buffer_adresses[0] = c.vkGetBufferDeviceAddress(core.device.handle, &device_address_info);
    return .{};
}
