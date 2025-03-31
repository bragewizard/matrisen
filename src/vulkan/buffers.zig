const std = @import("std");
const c = @import("clibs");
const geometry = @import("geometry");
const Vec3 = geometry.Vec3(f32);
const Vec4 = geometry.Vec4(f32);
const debug = @import("debug.zig");
const gltf = @import("../gltf.zig");
const Core = @import("core.zig");
const AsyncContext = @import("commands.zig").AsyncContext;
const FrameContext = @import("commands.zig").FrameContext;
const Mat4x4 = geometry.Mat4x4(f32);
const shapes = @import("../shapes.zig");
const commands = @import("commands.zig");
const common = @import("pipelines/common.zig");
const SceneDataUniform = common.SceneDataUniform;

uniform: [4]AllocatedBuffer = undefined,
storage: [4]StorageBuffer = undefined,
vertex: [4]AllocatedBuffer = undefined,
index: [1]AllocatedBuffer = undefined,
adresses: [2]c.VkDeviceAddress = undefined,
meshassets: [1]MeshAsset = undefined,

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

pub const MeshBuffers = struct {
    vertex_buffer: AllocatedBuffer,
    index_buffer: AllocatedBuffer,
    vertex_buffer_adress: c.VkDeviceAddress,
};

pub const StorageBuffer = struct {
    buffer: AllocatedBuffer,
    address: c.VkDeviceAddress,
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
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
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
    const address = c.vkGetBufferDeviceAddress(core.device.handle, &device_address_info);
    return .{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .vertex_buffer_adress = address,
    };
}

/// Uploads the given byte slice to a GPU-only Storage Buffer (SSBO).
/// Assumes the bufferDeviceAddress feature is enabled.
/// Returns the allocated buffer and its device address.
pub fn uploadSSBO(core: *Core, data_slice: []const u8) StorageBuffer {
    const data_size: c.VkDeviceSize = data_slice.len;
    const ssbo_buffer = create(
        core,
        data_size,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY, // Optimal for GPU access
    );

    const staging_buffer = create(
        core,
        data_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY, // Or VMA_MEMORY_USAGE_CPU_TO_GPU
    );
    defer c.vmaDestroyBuffer(core.gpuallocator, staging_buffer.buffer, staging_buffer.allocation);

    if (staging_buffer.info.pMappedData) |mapped_data_ptr| {
        const byte_data_ptr = @as([*]u8, @ptrCast(mapped_data_ptr));
        const staging_slice = byte_data_ptr[0..data_size];
        @memcpy(staging_slice, data_slice);

    } else {
        std.log.err("Failed to map staging buffer for SSBO upload.", .{});
        @panic("");
    }

    AsyncContext.submitBegin(core);
    const copy_region = c.VkBufferCopy{
        .srcOffset = 0,
        .dstOffset = 0,
        .size = data_size,
    };
    const cmd = core.asynccontext.command_buffer;
    c.vkCmdCopyBuffer(cmd, staging_buffer.buffer, ssbo_buffer.buffer, 1, &copy_region);
    AsyncContext.submitEnd(core);

    const device_address_info = c.VkBufferDeviceAddressInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .pNext = null, // Always initialize pNext
        .buffer = ssbo_buffer.buffer,
    };

    const address = c.vkGetBufferDeviceAddress(core.device.handle, &device_address_info);

    if (address == 0) {
        std.log.err("Failed to get buffer device address for SSBO. Is the feature enabled?", .{});
        c.vmaDestroyBuffer(core.gpuallocator, ssbo_buffer.buffer, ssbo_buffer.allocation);
        @panic("");
    }
    return .{
        .buffer = ssbo_buffer,
        .address = address,
    };
}

pub fn uploadSceneData(core: *Core, frame: *FrameContext, view: Mat4x4 ) void {
    frame.allocatedbuffers = create(
        core,
        @sizeOf(SceneDataUniform),
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    var scene_uniform_data: *SceneDataUniform = @alignCast(@ptrCast(frame.allocatedbuffers.info.pMappedData.?));
    scene_uniform_data.view = view;
    scene_uniform_data.proj = Mat4x4.perspective(
        std.math.degreesToRadians(60.0),
        @as(f32, @floatFromInt(frame.draw_extent.width)) / @as(f32, @floatFromInt(frame.draw_extent.height)),
        0.1,
        1000.0,
    );
    scene_uniform_data.viewproj = Mat4x4.mul(scene_uniform_data.proj, scene_uniform_data.view);
    scene_uniform_data.sunlight_dir = .{ .x = 0.1, .y = 0.1, .z = 1, .w = 1 };
    scene_uniform_data.sunlight_color = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    scene_uniform_data.ambient_color = .{ .x = 1, .y = 0.6, .z = 0, .w = 1 };
}

pub fn init(core: *Core) void {
    const m = gltf.load_meshes(core, "assets/suzanne.glb") catch @panic("Failed to load mesh");
    core.buffers.meshassets[0] = m.items[0];

    const my_line_geom = shapes.Line.new(.{ -20, -20, 0.0 }, .{ -20, 20, 0.0 });
    const line_array: [6*4]u8 = @bitCast(my_line_geom);
    const line_geometry_ssbo = uploadSSBO(core, &line_array);
    core.buffers.storage[0] = line_geometry_ssbo;
}

pub fn deinit(core: *Core) void {
    const self = &core.buffers;
    defer for (self.meshassets) |mesh| {
        mesh.surfaces.deinit();
    };

    defer c.vmaDestroyBuffer(core.gpuallocator, self.uniform[0].buffer, self.uniform[0].allocation);
    defer c.vmaDestroyBuffer(core.gpuallocator, self.storage[0].buffer.buffer, self.storage[0].buffer.allocation);
    defer for (self.meshassets) |mesh| {
        c.vmaDestroyBuffer(core.gpuallocator, mesh.mesh_buffers.vertex_buffer.buffer, mesh.mesh_buffers.vertex_buffer.allocation);
        c.vmaDestroyBuffer(core.gpuallocator, mesh.mesh_buffers.index_buffer.buffer, mesh.mesh_buffers.index_buffer.allocation);
    };
}
