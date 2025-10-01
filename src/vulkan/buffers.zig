//! Bindless design
//! Create large buffers
//! Pass indices or addresses or both via a storage buffer
//! use drawinderect to access that buffer and get the indices for materials
//! and vertices osv...
//!
//! TODO make function for creating model buffer
//! TODO make function for creating material buffer
//!

const std = @import("std");
const c = @import("clibs").libs;
const geometry = @import("linalg");
const commands = @import("commands.zig");
const debug = @import("debug.zig");
const Vec3 = geometry.Vec3(f32);
const Vec4 = geometry.Vec4(f32);
const Core = @import("core.zig");
const AsyncContext = @import("commands.zig").AsyncContext;
const FrameContext = @import("commands.zig").FrameContext;
const Mat4x4 = geometry.Mat4x4(f32);

const Self = @This();
pub const frames_in_flight = 2; // TODO: move this to app land

/// Dynamic TODO: move this to app section not lib
const Scene = struct {
    vertex: AllocatedBuffer, // Vulkan buffer for vertices
    index: AllocatedBuffer, // Vulkan buffer for indices
    pose: AllocatedBuffer, // Storage buffer for poses
    resourcetable: AllocatedBuffer, // Storage buffer for ResourceEntry
    indirect: AllocatedBuffer, // Indirect draw commands
    vertex_address: c.VkDeviceAddress,
    index_address: c.VkDeviceAddress, // Optional, if needed in shader
    pose_address: c.VkDeviceAddress,
    resource_entries: []ResourceEntry,
    poses: []Mat4x4,
    indirect_commands: []c.VkDrawIndexedIndirectCommand,
    allocator: std.mem.Allocator, // For dynamic allocations
};

/// Stays mostly constant
pub const GlobalBuffers = struct {
    indirect: AllocatedBuffer = undefined,
    vertex: AllocatedBuffer = undefined,
    index: AllocatedBuffer = undefined, //FIX figure out what to do about indexbuffers as they need to be bound
    resourcetable: AllocatedBuffer = undefined,
};

/// Varies per frame
pub const PerFrameBuffers = struct {
    poses: AllocatedBuffer = undefined,
    scenedata: AllocatedBuffer = undefined,
};

pub const ResourceEntry = extern struct {
    pose: u32,
    object: u32,
    vertex_offset: u32,
};

pub const AllocatedBuffer = struct {
    buffer: c.VkBuffer, //TODO change to "handle"
    allocation: c.VmaAllocation,
    info: c.VmaAllocationInfo,
};

pub const Vertex = extern struct {
    position: Vec3,
    uv_x: f32,
    normal: Vec3,
    uv_y: f32,
    color: Vec4,

    pub fn new(p0: Vec3, p1: Vec3, p2: Vec4, x: f32, y: f32) Vertex {
        return .{
            .position = p0,
            .normal = p1,
            .color = p2,
            .uv_x = x,
            .uv_y = y,
        };
    }
};

pub const SceneDataUniform = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sunlight_dir: Vec4,
    sunlight_color: Vec4,
    pose_buffer_address: c.VkDeviceAddress,
    vertex_buffer_address: c.VkDeviceAddress,
};

pub const MaterialConstantsUniform = extern struct {
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
};

pub const GeoSurface = struct {
    start_index: u32,
    count: u32,
};

pub const MeshAsset = struct {
    surfaces: std.ArrayList(GeoSurface),
    vertices: []Vertex = undefined,
    indices: []u32 = undefined,
};

pub fn createIndirect(core: *Core, command_count: u32) AllocatedBuffer {
    const indirect_buffer = create(
        core,
        @sizeOf(c.VkDrawIndexedIndirectCommand) * command_count, // COMMAND_COUNT is how many draw calls
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY,
    );
    return indirect_buffer;
}

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

pub fn createIndex(core: *Core, size: c.VkDeviceSize) AllocatedBuffer {
    const index_buffer = create(
        core,
        size,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        c.VMA_MEMORY_USAGE_GPU_ONLY,
    );
    return index_buffer;
}

pub fn upload(core: *Core, data_slice: []const u8, buffer: AllocatedBuffer) void {
    const size = data_slice.len;
    const staging_buffer = create(
        core,
        size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VMA_MEMORY_USAGE_CPU_ONLY, // Or VMA_MEMORY_USAGE_CPU_TO_GPU
    );
    defer c.vmaDestroyBuffer(core.gpuallocator, staging_buffer.buffer, staging_buffer.allocation);

    if (staging_buffer.info.pMappedData) |mapped_data_ptr| {
        const byte_data_ptr = @as([*]u8, @ptrCast(mapped_data_ptr));
        const staging_slice = byte_data_ptr[0..size];
        @memcpy(staging_slice, data_slice);
    } else {
        std.log.err("Failed to map staging buffer for SSBO upload.", .{});
        @panic("");
    }

    AsyncContext.submitBegin(core);
    const copy_region = c.VkBufferCopy{
        .srcOffset = 0,
        .dstOffset = 0,
        .size = size,
    };
    const cmd = core.asynccontext.command_buffer;
    c.vkCmdCopyBuffer(cmd, staging_buffer.buffer, buffer.buffer, 1, &copy_region);
    AsyncContext.submitEnd(core);
}

pub fn createSSBO(core: *Core, size: c.VkDeviceSize, device_address: bool) AllocatedBuffer {
    var ssbo_buffer: AllocatedBuffer = undefined;
    if (device_address) {
        ssbo_buffer = create(
            core,
            size,
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c.VMA_MEMORY_USAGE_GPU_ONLY, // Optimal for GPU access
        );
    } else {
        ssbo_buffer = create(
            core,
            size,
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            c.VMA_MEMORY_USAGE_GPU_ONLY, // Optimal for GPU access
        );
    }
    return ssbo_buffer;
}

pub fn getDeviceAddress(core: *Core, buffer: AllocatedBuffer) c.VkDeviceAddress {
    const device_address_info = c.VkBufferDeviceAddressInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .pNext = null, // Always initialize pNext
        .buffer = buffer.buffer,
    };
    const adr = c.vkGetBufferDeviceAddress(core.device.handle, &device_address_info);
    if (adr == 0) {
        std.log.err("Failed to get buffer device address for SSBO. Is the feature enabled?", .{});
        c.vmaDestroyBuffer(core.gpuallocator, buffer.buffer, buffer.allocation);
        @panic("");
    }
    return adr;
}
