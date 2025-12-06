const std = @import("std");
const linalg = @import("../linalg.zig");
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;
const DescriptorWriter = @import("DescriptorWriter.zig");
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const Mat4x4 = linalg.Mat4x4(f32);
const Core = @import("Core.zig");
const Device = @import("Device.zig");
const AllocatedBuffer = @import("BufferAllocator.zig").AllocatedBuffer;
const BufferAllocator = @import("BufferAllocator.zig");
const DescriptorManager = @import("DescriptorManager.zig");

pub const MaterialConstants = extern struct {
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
};

pub const SceneData = extern struct {
    view: Mat4x4 = .zeros,
    proj: Mat4x4 = .zeros,
    viewproj: Mat4x4 = .zeros,
    ambient_color: Vec4 = .zeros,
    sunlight_dir: Vec4 = .zeros,
    sunlight_color: Vec4 = .zeros,
};

pub const MeshData = extern struct {
    vertexbuffer: u64 = 0, // 64-bit address
    indexbuffer: u64 = 0, // 64-bit address
    // Bounding box, LOD info, etc. could go here
};

pub const InstanceData = extern struct {
    modelmatrix: Mat4x4 = .zeros,
    meshindex: u32 = 0,
    materialindex: u32 = 0,
    _pad0: u32 = 0, // Padding for 16-byte alignment
    _pad1: u32 = 0,
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

pub const GeoSurface = struct {
    start_index: u32,
    count: u32,
};

pub const MeshAsset = struct {
    surfaces: std.ArrayList(GeoSurface),
    vertices: []Vertex = undefined,
    indices: []u32 = undefined,
};

const Self = @This();

const MAX_VERTICES = 10_000;
const MAX_INDICES = 10_000;
const MAX_INSTANCES = 1000;

globalvertexbuffer: AllocatedBuffer = undefined,
globalindexbuffer: AllocatedBuffer = undefined,
// 1. Static Geometry (Huge, GPU Local, Single Buffered)
globalstaticvertex: AllocatedBuffer = undefined,
globalstaticindex: AllocatedBuffer = undefined,
// 2. Dynamic Geometry (Smaller, CPU Visible, Ring Buffered)
// We treat this as one giant linear buffer that we loop through.
globaldynamicvertex: AllocatedBuffer = undefined,
globaldynamicindex: AllocatedBuffer = undefined,
// Trackers for the Ring Buffer
dynamicvertexoffset: u32 = 0,
dynamicindexoffset: u32 = 0,

// contains array of u64 addresses to peek into global buffer
meshtablebuffer: AllocatedBuffer = undefined,
instancetablebuffer: AllocatedBuffer = undefined,
// contains data updated evry frame trough uniform
scenebuffers: [Core.multibuffering]AllocatedBuffer = @splat(undefined),
indirectbuffer: AllocatedBuffer = undefined,

pub fn init() Self {
    return .{};
}

pub fn destroyBuffers(self: *Self, bufferallocator: *BufferAllocator) void {
    for (self.scenebuffers) |buf| bufferallocator.destroy(buf);
    bufferallocator.destroy(self.globalvertexbuffer);
    bufferallocator.destroy(self.globalindexbuffer);
    bufferallocator.destroy(self.meshtablebuffer);
    bufferallocator.destroy(self.instancetablebuffer);
    bufferallocator.destroy(self.indirectbuffer);
}

/// DEBUG dummy data
pub fn initDummy(self: *Self, bufferallocator: *BufferAllocator, descriptormanager: *DescriptorManager) void {
    const scenedata: SceneData = .{};
    const meshdata: MeshData = .{};
    const instancedata: InstanceData = .{};
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = bufferallocator.create(
            @sizeOf(SceneData),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        descriptormanager.writeDynamicSet(buf.*, @intCast(i));
        const scenedataptr: *SceneData = @ptrCast(@alignCast(buf.info.pMappedData.?));
        scenedataptr.* = scenedata;
    }
    self.meshtablebuffer = bufferallocator.create(
        @sizeOf(MeshData),
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    self.instancetablebuffer = bufferallocator.create(
        @sizeOf(InstanceData),
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    const meshdataptr: *MeshData = @ptrCast(@alignCast(self.meshtablebuffer.info.pMappedData.?));
    const instancedataptr: *InstanceData = @ptrCast(
        @alignCast(self.instancetablebuffer.info.pMappedData.?),
    );
    meshdataptr.* = meshdata;
    instancedataptr.* = instancedata;
    descriptormanager.writeStaticSet(self.meshtablebuffer, self.instancetablebuffer);
}

/// DEBUG test data
pub fn initTest(
    self: *Self,
    bufferallocator: *BufferAllocator,
    descriptormanager: *DescriptorManager,
) !void {
    // --- 1. Create Scene Buffers (Double Buffered) ---
    const scenedata: SceneData = .{};
    for (&self.scenebuffers, 0..) |*buf, i| {
        buf.* = bufferallocator.create(
            @sizeOf(SceneData),
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
        const scenedataptr: *SceneData = @ptrCast(@alignCast(buf.info.pMappedData.?));
        scenedataptr.* = scenedata;
        descriptormanager.writeDynamicSet(buf.*, @intCast(i));
    }

    // --- 2. Create Global Geometry Buffers ---
    // Note: Must include SHADER_DEVICE_ADDRESS_BIT to get the u64 pointer!
    self.globalvertexbuffer = bufferallocator.create(
        @sizeOf(Vertex) * MAX_VERTICES,
        c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT |
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, // Simple CPU write for now
    );

    self.globalindexbuffer = bufferallocator.create(
        @sizeOf(u32) * MAX_INDICES,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT |
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
            c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU, // Simple CPU write for now
    );

    // --- 3. Upload Cube Data ---
    // Get mapped pointers
    const v_ptr = @as([*]Vertex, @ptrCast(@alignCast(self.globalvertexbuffer.info.pMappedData.?)));
    const i_ptr = @as([*]u32, @ptrCast(@alignCast(self.globalindexbuffer.info.pMappedData.?)));

    // Define Cube (8 vertices)
    const cube_verts = [_]Vertex{
        Vertex.new(
            .{ .x = -0.5, .y = -0.5, .z = 0.5 },
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .x = 1, .y = 0, .z = 0, .w = 1 },
            0,
            0,
        ), // 0
        Vertex.new(
            .{ .x = 0.5, .y = -0.5, .z = 0.5 },
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .x = 0, .y = 1, .z = 0, .w = 1 },
            1,
            0,
        ), // 1
        Vertex.new(
            .{ .x = 0.5, .y = 0.5, .z = 0.5 },
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .x = 0, .y = 0, .z = 1, .w = 1 },
            1,
            1,
        ), // 2
        Vertex.new(
            .{ .x = -0.5, .y = 0.5, .z = 0.5 },
            .{ .x = 0, .y = 0, .z = 1 },
            .{ .x = 1, .y = 1, .z = 0, .w = 1 },
            0,
            1,
        ), // 3
        Vertex.new(
            .{ .x = 0.5, .y = -0.5, .z = -0.5 },
            .{ .x = 0, .y = 0, .z = -1 },
            .{ .x = 1, .y = 0, .z = 1, .w = 1 },
            0,
            0,
        ), // 4
        Vertex.new(
            .{ .x = -0.5, .y = -0.5, .z = -0.5 },
            .{ .x = 0, .y = 0, .z = -1 },
            .{ .x = 0, .y = 1, .z = 1, .w = 1 },
            1,
            0,
        ), // 5
        Vertex.new(
            .{ .x = -0.5, .y = 0.5, .z = -0.5 },
            .{ .x = 0, .y = 0, .z = -1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            1,
            1,
        ), // 6
        Vertex.new(
            .{ .x = 0.5, .y = 0.5, .z = -0.5 },
            .{ .x = 0, .y = 0, .z = -1 },
            .{ .x = 0, .y = 0, .z = 0, .w = 1 },
            0,
            1,
        ), // 7
    };
    // 36 indices
    const cube_indices = [_]u32{
        0, 1, 2, 2, 3, 0, // Front
        1, 4, 7, 7, 2, 1, // Right
        4, 5, 6, 6, 7, 4, // Back
        5, 0, 3, 3, 6, 5, // Left
        5, 4, 1, 1, 0, 5, // Bottom
        3, 2, 7, 7, 6, 3, // Top
    };

    @memcpy(v_ptr[0..cube_verts.len], &cube_verts);
    @memcpy(i_ptr[0..cube_indices.len], &cube_indices);

    // We need the base pointer of the buffer to store in our MeshTable
    const vertex_addr = bufferallocator.getBufferAddress(self.globalvertexbuffer);
    const index_addr = bufferallocator.getBufferAddress(self.globalindexbuffer);

    // --- 5. reate & Fill Tables ---
    self.meshtablebuffer = bufferallocator.create(
        @sizeOf(MeshData) * MAX_INSTANCES,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    // 1. Calculate size for Double/Triple Buffering
    // If we support 1000 objects, and have 2 frames in flight, we need space for 2000.
    const total_instances = MAX_INSTANCES * Core.multibuffering;

    // 2. Allocate the GIANT Instance Buffer
    self.instancetablebuffer = bufferallocator.create(
        @sizeOf(InstanceData) * total_instances, // <--- BIGGER SIZE
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    self.indirectbuffer = bufferallocator.create(
        @sizeOf(c.VkDrawIndirectCommand) * MAX_INSTANCES,
        c.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    // Write tables to Descriptor Set 1
    descriptormanager.writeStaticSet(self.meshtablebuffer, self.instancetablebuffer);

    // --- 6. Set up the Scene Objects ---
    const mesh_ptr = @as([*]MeshData, @ptrCast(@alignCast(self.meshtablebuffer.info.pMappedData.?)));
    const inst_ptr = @as([*]InstanceData, @ptrCast(@alignCast(self.instancetablebuffer.info.pMappedData.?)));
    const cmd_ptr = @as([*]c.VkDrawIndirectCommand, @ptrCast(@alignCast(self.indirectbuffer.info.pMappedData.?)));

    // Mesh Entry 0: The Cube
    // Since we only uploaded one mesh at offset 0, the address is Base + 0
    mesh_ptr[0] = MeshData{
        .vertexbuffer = vertex_addr,
        .indexbuffer = index_addr,
    };

    // Create 3 Instances
    for (0..3) |i| {
        // Init Instance (Matrices will be updated in rotateDummy)
        inst_ptr[i] = InstanceData{
            .modelmatrix = Mat4x4.identity,
            .meshindex = 0, // All 3 use Mesh 0 (Cube)
            .materialindex = 0,
            ._pad0 = 0,
            ._pad1 = 0, // Padding init
        };

        // Init Draw Command
        cmd_ptr[i] = c.VkDrawIndirectCommand{
            .vertexCount = cube_indices.len, // 36 indices
            .instanceCount = 1,
            .firstVertex = 0, // Offset in vertex array (0 since we fetched indices manually)
            .firstInstance = 0, // We use gl_DrawID instead of gl_InstanceIndex
        };
    }
}

pub fn rotateDummy(self: *Self, frameindex: u8, frame: u64) void {
    const base_ptr = @as([*]InstanceData, @ptrCast(@alignCast(self.instancetablebuffer.info.pMappedData.?)));
    const frame_offset = frameindex * MAX_INSTANCES;
    const inst_ptr = base_ptr + frame_offset; // Pointer arithmetic
    // Simple time based on system timestamp
    const time = @as(f32, @floatFromInt(frame)) / 1000.0;
    const angle = time * std.math.pi; // Half rotation per second

    // Cube 1: Left (-2, 0, 0), Rotate Y
    {
        // 1. Create Rotation
        const rot = Mat4x4.rotation(Vec3.unit_y, angle);
        // 2. Create Translation
        const trans = Mat4x4.translation(Vec3.new(-2.0, 0.0, 0.0));

        // 3. Combine: T * R
        inst_ptr[0].modelmatrix = trans.mul(rot);
    }

    // Cube 2: Center (0, 0, 0), Rotate X
    {
        // No translation needed (identity), just rotation
        inst_ptr[1].modelmatrix = Mat4x4.rotation(Vec3.unit_x, angle);
    }

    // Cube 3: Right (2, 0, 0), Rotate Z
    {
        const rot = Mat4x4.rotation(Vec3.unit_z, angle);
        const trans = Mat4x4.translation(Vec3.new(2.0, 0.0, 0.0));

        inst_ptr[2].modelmatrix = trans.mul(rot);
    }
}

pub fn updateScene(self: *Self, frame_index: usize, aspect_ratio: f32) void {
    const ptr = @as(*SceneData, @ptrCast(@alignCast(self.scenebuffers[frame_index].info.pMappedData.?)));

    // 1. Camera Setup
    const cam_pos = Vec3.new(0.0, 2.0, -5.0); // Eye
    const target = Vec3.new(0.0, 0.0, 0.0); // Center
    const up = Vec3.new(0.0, 1.0, 0.0); // Up

    // 2. View Matrix
    const view = Mat4x4.lookAt(cam_pos, target, up);

    // 3. Projection Matrix
    // FOV 70 degrees converted to radians
    const fov_radians = 70.0 * (std.math.pi / 180.0);
    var proj = Mat4x4.perspective(fov_radians, aspect_ratio, 0.1, 1000.0);

    // Vulkan Y-Flip Correction
    // (Vulkan's Y coordinate is down, but standard perspective math assumes Y is up)
    proj.y.y *= -1.0;

    // 4. Write to Buffer
    ptr.view = view;
    ptr.proj = proj;

    // Note: Your library's mul() is likely Column-Major (M1 * M2),
    // so Proj * View is usually the correct order for (proj.mul(view)).
    ptr.viewproj = proj.mul(view);

    // 5. Lighting Data
    // Using Vec4.new(x,y,z,w)
    ptr.ambient_color = Vec4.new(1.0, 0.5, 0.0, 1.0);
    ptr.sunlight_color = Vec4.new(1.0, 1.0, 0.9, 1.0);

    // Sunlight direction (Pointing down-ish)
    const sun_dir = Vec3.new(0.5, -1.0, 0.2).normalized();
    ptr.sunlight_dir = sun_dir.toVec4(0.0);
}

// pub fn updateScene(self: *Self, core: *Core, comptime data: T) void {
//     const current = core.framecontexts.current;
//     var frame = &core.framecontexts.frames[current];
//     var scene_uniform_data: *T = @ptrCast(@alignCast(self.data[current].scenedata.info.pMappedData.?));
//     scene_uniform_data.view = view;
//     scene_uniform_data.proj = Mat4x4.perspective(
//         std.math.degreesToRadians(60.0),
//         @as(f32, @floatFromInt(frame.draw_extent.width)) / @as(f32, @floatFromInt(frame.draw_extent.height)),
//         0.1,
//         1000.0,
//     );
//     scene_uniform_data.viewproj = Mat4x4.mul(scene_uniform_data.proj, scene_uniform_data.view);
//     scene_uniform_data.sunlight_dir = .{ .x = 0.1, .y = 0.1, .z = 1, .w = 1 };
//     scene_uniform_data.sunlight_color = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
//     scene_uniform_data.ambient_color = .{ .x = 1, .y = 0.6, .z = 0, .w = 1 };

//     var poses: *[2]Mat4x4 = @ptrCast(@alignCast(self.data[current].poses.info.pMappedData.?));

//     var time: f32 = @floatFromInt(core.framenumber);
//     time /= 100;
//     var mod = Mat4x4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, time / 2.0);
//     mod = mod.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, time);
//     mod = mod.translate(.{ .x = 2.0, .y = 2.0, .z = 2.0 });
//     poses[0] = Mat4x4.identity;
//     poses[1] = mod;
// }
