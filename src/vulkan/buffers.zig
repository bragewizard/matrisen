const std = @import("std");
const c = @import("clibs");
const geometry = @import("geometry");
const Vec3 = geometry.Vec3(f32);
const Vec4 = geometry.Vec4(f32);
const debug = @import("debug.zig");
const gltf = @import("../gltf.zig");
const Core = @import("core.zig");
const AsyncContext = @import("commands.zig").AsyncContext;
const commands = @import("commands.zig");
const Self = @This();

allocatedbuffers: [4]AllocatedBuffer = undefined,
vertex_buffers: [4]AllocatedBuffer = undefined,
index_buffers: [1]AllocatedBuffer = undefined,
vertex_buffer_adresses: [2]c.VkDeviceAddress = undefined,
meshassets: [1]MeshAsset = undefined,

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

pub const MeshBuffers = struct {
    vertex_buffer: u32,
    index_buffer: u32,
    vertex_buffer_adress: u32,
};

pub const GeoSurface = struct {
    start_index: u32,
    count: u32,
};

pub const MeshAsset = struct {
    surfaces: std.ArrayList(GeoSurface),
    mesh_buffers: MeshBuffers = undefined,
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

pub fn upload_mesh(core: *Core, indices: []u32, vertices: []Vertex) MeshBuffers {
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
    AsyncContext.submitBegin(core);
    const vertex_copy_region: c.VkBufferCopy = .{
        .srcOffset = 0,
        .dstOffset = 0,
        .size = vertex_buffer_size,
    };

    const index_copy_region: c.VkBufferCopy = .{
        .srcOffset = vertex_buffer_size,
        .dstOffset = 0,
        .size = index_buffer_size,
    };
    const cmd = core.asynccontext.command_buffer;
    c.vkCmdCopyBuffer(cmd, staging.buffer, vertex_buffer.buffer, 1, &vertex_copy_region);
    c.vkCmdCopyBuffer(cmd, staging.buffer, index_buffer.buffer, 1, &index_copy_region);
    AsyncContext.submitEnd(core);
    core.buffers.vertex_buffers[0] = vertex_buffer;
    core.buffers.index_buffers[0] = index_buffer;
    core.buffers.vertex_buffer_adresses[0] = c.vkGetBufferDeviceAddress(core.device.handle, &device_address_info);
    return .{
        .vertex_buffer = 0,
        .index_buffer = 0,
        .vertex_buffer_adress = 0,
    };
}

pub fn init(core: *Core) void {
    const m = gltf.load_meshes(core, "assets/suzanne.glb") catch @panic("Failed to load mesh");
    core.buffers.meshassets[0] = m.items[0];
}

pub fn deinit(core: *Core) void {
    _ = core;
}
