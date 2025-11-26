const c = @import("../clibs/clibs.zig");
const Core = @import("Core.zig");
const FrameContext = @import("command.zig").FrameContext;
const descriptor = @import("descriptor.zig");
const vk_alloc_cbs = Core.vkallocationcallbacks;

const Self = @This();

pipelinelayout: c.VkPipelineLayout = undefined,
defaultpipeline: c.VkPipeline = undefined,
resourcelayout: c.VkDescriptorSetLayout = undefined,
scenedatalayout: c.VkDescriptorSetLayout = undefined,
static_set: c.VkDescriptorSet = undefined,
globaldescriptorallocator: descriptor.Allocator = .{},

pub fn deinit(self: *Self, core: *Core) void {
    c.vkDestroyDescriptorSetLayout(core.device.handle, self.scenedatalayout, vk_alloc_cbs);
    c.vkDestroyDescriptorSetLayout(core.device.handle, self.resourcelayout, vk_alloc_cbs);
    c.vkDestroyPipelineLayout(core.device.handle, self.layout, vk_alloc_cbs);
    c.vkDestroyPipeline(core.device.handle, self.pipeline, vk_alloc_cbs);
}

pub fn draw(self: *Self, core: *Core, frame: *FrameContext) void {
    const cmd = frame.command_buffer;
    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout, 0, 1, &frame.sets[0], 0, null);
    c.vkCmdBindDescriptorSets(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.layout, 1, 1, &core.sets[0], 0, null);
    c.vkCmdBindIndexBuffer(cmd, core.buffers.index.buffer, 0, c.VK_INDEX_TYPE_UINT32);
    c.vkCmdDrawIndexedIndirect(cmd, core.buffers.indirect.buffer, 0, 1, @sizeOf(c.VkDrawIndexedIndirectCommand));
    // c.vkCmdDrawIndexed(cmd, 1, 1, 0, 0, 0);
    // c.vkCmdDraw(cmd, 24, 1, 0, 0);
}

// fn initPipelineLayout(self: *Self) void {
//     {
//         var builder: descriptor.LayoutBuilder = .init();
//         defer builder.deinit(self.cpuallocator);
//         builder.add_binding(self.cpuallocator, 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
//         self.scenedatalayout = builder.build(
//             self.device.handle,
//             c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
//             null,
//             0,
//         );
//     }
//     {
//         var builder: descriptor.LayoutBuilder = .init();
//         defer builder.deinit(self.cpuallocator);
//         builder.add_binding(self.cpuallocator, 0, c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
//         self.resourcelayout = builder.build(
//             self.device.handle,
//             c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
//             null,
//             0,
//         );
//     }
// }

// fn writeSets(self: *Self) void {
//     var pipeline = &self.pipelines.vertexshader;
//     pipeline.writeSetSBBO(&self, self.sdata.resourcetable, buffer.ResourceEntry);
//     for (0.., &self.data) |i, *data| {
//         const adr = buffer.getDeviceAddress(self, self.data[i].poses);
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

// fn initDescriptor(self: *Self) void {
//     var sizes = [_]Allocator.PoolSizeRatio{
//         .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
//         .{ .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
//     };
//     self.globaldescriptorallocator.init(self.device.handle, 10, &sizes, self.cpuallocator);

//     var ratios = [_]Allocator.PoolSizeRatio{
//         .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE },
//         .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER },
//         .{ .ratio = 3, .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER },
//         .{ .ratio = 4, .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER },
//     };

//     self.staticset = self.globaldescriptorallocator.allocate(
//         self.cpuallocator,
//         eslf.device.handle,
//         self.resourcelayout,
//         null,
//     );

//     for (0.., &self.dynamicdescriptorallocators) |i, *element| {
//         element.init(core.device.handle, 1000, &ratios, core.cpuallocator);
//         self.dynamic_sets[i] = element.allocate(
//             core.cpuallocator,
//             core.device.handle,
//             self.scenedatalayout,
//             null,
//         );
//     }
// }
