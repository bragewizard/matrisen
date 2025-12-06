const std = @import("std");
const log = std.log.scoped(.descriptormanager);
const debug = @import("debug.zig");
const c = @import("../clibs/clibs.zig").libs;
const Core = @import("Core.zig");
const DescriptorAllocator = @import("DescriptorAllocator.zig");
const Device = @import("Device.zig");
const PipelineManager = @import("PipelineManager.zig");
const BufferAllocator = @import("BufferAllocator.zig");
const DescriptorWriter = @import("DescriptorWriter.zig");
const BufferManager = @import("BufferManager.zig");

const Self = @This();

allocator: std.mem.Allocator,
device: c.VkDevice,
staticset: c.VkDescriptorSet,
staticallocator: DescriptorAllocator,
dynamicallocators: [Core.multibuffering]DescriptorAllocator,
dynamicsets: [Core.multibuffering]c.VkDescriptorSet,

pub fn init(allocator: std.mem.Allocator, device: Device, pipelinemanager: PipelineManager) Self {
    var staticratios = [_]DescriptorAllocator.PoolSizeRatio{
        .{ .ratio = 2, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER },
    };
    var dynamicratios = [_]DescriptorAllocator.PoolSizeRatio{
        .{ .ratio = 1, .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER },
    };
    var staticallocator: DescriptorAllocator = .init(device.handle, 10, &staticratios, allocator);
    const staticset = staticallocator.allocate(
        allocator,
        device.handle,
        pipelinemanager.staticlayout,
        null,
    );
    var dynamicsets: [Core.multibuffering]c.VkDescriptorSet = @splat(undefined);
    var dynamicallocators: [Core.multibuffering]DescriptorAllocator = @splat(.{});
    for (&dynamicsets, &dynamicallocators) |*set, *dynamicdescriptorallocator| {
        dynamicdescriptorallocator.* = .init(device.handle, 1000, &dynamicratios, allocator);
        set.* = dynamicdescriptorallocator.allocate(
            allocator,
            device.handle,
            pipelinemanager.dynamiclayout,
            null,
        );
    }
    return .{
        .staticallocator = staticallocator,
        .dynamicallocators = dynamicallocators,
        .staticset = staticset,
        .dynamicsets = dynamicsets,
        .allocator = allocator,
        .device = device.handle,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: Device) void {
    self.staticallocator.deinit(device.handle, allocator);
    for (&self.dynamicallocators) |*dynamicallocator| dynamicallocator.deinit(device.handle, allocator);
}

pub fn writeStaticSet(
    self: *Self,
    meshbuffer: BufferAllocator.AllocatedBuffer, // Binding 0
    instancebuffer: BufferAllocator.AllocatedBuffer, // Binding 1
) void {
    var writer = DescriptorWriter.init();
    defer writer.deinit(self.allocator);
    writer.writeBuffer(
        self.allocator, // Use the passed allocator, not self.cpuallocator (unless intentional)
        0, // Binding Index
        meshbuffer.buffer,
        c.VK_WHOLE_SIZE,
        0, // Offset
        c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    );

    writer.writeBuffer(
        self.allocator,
        1, // Binding Index
        instancebuffer.buffer,
        c.VK_WHOLE_SIZE,
        0,
        c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    );
    writer.updateSet(self.device, self.staticset);
}
pub fn writeDynamicSet(
    self: *Self,
    data: BufferAllocator.AllocatedBuffer,
    frame: u8,
) void {
    var writer = DescriptorWriter.init();
    defer writer.deinit(self.allocator);
    writer.writeBuffer(
        self.allocator,
        0,
        data.buffer,
        @sizeOf(BufferManager.SceneData),
        0,
        c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    );
    writer.updateSet(self.device, self.dynamicsets[frame]);
}

// fn writeSets(self: *Self) void {
//     var pipeline = &self.pipelines.vertexshader;
//     pipeline.writeSetSBBO(&self, self.sdata.resourcetable, buffer.ResourceEntry);
//     for (0.., &self.data) |i, *data| {
//         const adr = buffer.getDeviceAddress(self, data[i].poses);
//         var scene_uniform_data: *SceneDataUniform = @ptrCast(@alignCast(data.scenedata.info.pMappedData.?));
//         scene_uniform_data.pose_buffer_address = adr;
//         {
//             var writer = Writer.init();
//             defer writer.deinit(core.cpuallocator);
//             writer.writeBuffer(
//                 core.cpuallocator,
//                 0,
//                 data.scenedata.buffer,
//                 @sizeOf(SceneDataUniform),
//                 0,
//                 c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
//             );
//             writer.updateSet(core.device.handle, pipeline.dynamic_sets[i]);
//         }
//     }
// }
