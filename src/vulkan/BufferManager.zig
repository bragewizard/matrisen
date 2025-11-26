/// This module should take care of all created buffers, the design ideology is bindless with
/// large buffers that gets allocated once and filled with indexoffsets, the descriptor
const AllocatedBuffer = @import("buffer.zig");
const Core = @import("Core.zig");
const c = @import("../clibs/clibs.zig");
const Self = @This();

indexoffset: usize,
vertexoffset: usize,
staticvertexbuffer: AllocatedBuffer,
staticindexbuffer: AllocatedBuffer,
dynamicvertexbuffers: [Core.multibuffering]AllocatedBuffer,
dynamicindexbuffers: [Core.multibuffering]AllocatedBuffer,
pose_buffer_address: c.VkDeviceAddress, // this should be for all applications
vertex_buffer_address: c.VkDeviceAddress, //this should be for all applications

pub fn destroyBuffers(self: *Self, core: *Core) void {
    c.vmaDestroyBuffer(core.gpuallocator, self.buffers.scenedata.buffer, self.buffers.scenedata.allocation);
    c.vmaDestroyBuffer(core.gpuallocator, self.buffers.poses.buffer, self.buffers.poses.allocation);
}

pub fn uploadSceneData(self: *Self, core: *Core, comptime data: T) void {
    const current = core.framecontexts.current;
    var frame = &core.framecontexts.frames[current];
    var scene_uniform_data: *T = @ptrCast(@alignCast(self.data[current].scenedata.info.pMappedData.?));
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

    var poses: *[2]Mat4x4 = @ptrCast(@alignCast(self.data[current].poses.info.pMappedData.?));

    var time: f32 = @floatFromInt(core.framenumber);
    time /= 100;
    var mod = Mat4x4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, time / 2.0);
    mod = mod.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, time);
    mod = mod.translate(.{ .x = 2.0, .y = 2.0, .z = 2.0 });
    poses[0] = Mat4x4.identity;
    poses[1] = mod;
}



    core.buffers.indirect = m.buffer.createIndirect(core, 1);
    const resourses1: m.buffer.ResourceEntry = .{ .pose = 0, .object = 0, .vertex_offset = 0 };
    const resourses2: m.buffer.ResourceEntry = .{ .pose = 1, .object = 1, .vertex_offset = 199 };
    const resources: [2]m.buffer.ResourceEntry = .{ resourses1, resourses2 };
    const resources_slice = std.mem.sliceAsBytes(&resources);

    self.sdata.resourcetable = m.buffer.createSSBO(core, resources_slice.len, true);
    m.buffer.upload(core, resources_slice, core.buffers.resourcetable);

    for (&self.data) |*data| {
        data.scenedata = buffer.create(
            core,
            @sizeOf(SceneDataUniform),
            m.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            m.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );

        data.poses = buffer.create(
            core,
            @sizeOf(Mat4x4) * 2,
            c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT |
                c.VK_BUFFER_USAGE_TRANSFER_DST_BIT |
                c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        );
    }

pub fn writeSetSBBO(self: *Self, core: *Core, data: buffer.AllocatedBuffer, T: type) void {
    var writer = descriptor.Writer.init();
    defer writer.deinit(core.cpuallocator);
    writer.writeBuffer(
        core.cpuallocator,
        0,
        data,
        @sizeOf(T) * 2,
        0,
        c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    );
    writer.updateSet(core.device.handle, self.static_set);
}

// pub fn writeSetUniform(self: *Self, core: *Core, data: buffers.AllocatedBuffer, T: type) void {
//     var writer = Writer.init();
//     defer writer.deinit(core.cpuallocator);
//     writer.writeBuffer(
//         core.cpuallocator,
//         0,
//         data.scenedata.buffer,
//         @sizeOf(SceneDataUniform),
//         0,
//         c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
//     );
//     writer.updateSet(core.device.handle, pipeline.dynamic_sets[i]);
// }
