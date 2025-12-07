const std = @import("std");
const c = @import("../clibs/clibs.zig").libs;
const defaultpipline = @import("pipelines/default.zig");
const checkVkPanic = @import("debug.zig").checkVkPanic;
const Core = @import("Core.zig");
const FrameContext = @import("FrameContext.zig");
const DescriptorLayoutBuilder = @import("DescriptorLayoutBuilder.zig");
const AllocatedBuffer = @import("BufferAllocator.zig").AllocatedBuffer;

const Self = @This();

pipelinelayout: c.VkPipelineLayout,
descriptorlayout: c.VkDescriptorSetLayout,
defaultpipeline: c.VkPipeline,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
    var descriptorlayout: c.VkDescriptorSetLayout = undefined;
    {
        var builder: DescriptorLayoutBuilder = .init();
        defer builder.deinit(allocator);
        builder.addBinding(allocator, 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        descriptorlayout = builder.build(
            device,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    const descriptorlayouts: [1]c.VkDescriptorSetLayout = .{descriptorlayout};
    const layoutinfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 1,
        .pSetLayouts = &descriptorlayouts,
        .pushConstantRangeCount = 0,
    };

    var pipelinelayout: c.VkPipelineLayout = undefined;
    checkVkPanic(c.vkCreatePipelineLayout(device, &layoutinfo, null, &pipelinelayout));
    const pipeline = defaultpipline.init(device, pipelinelayout, allocationcallbacks);

    return .{
        .defaultpipeline = pipeline,
        .pipelinelayout = pipelinelayout,
        .descriptorlayout = descriptorlayout,
    };
}

pub fn deinit(self: *Self, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyDescriptorSetLayout(device, self.descriptorlayout, allocationcallbacks);
    c.vkDestroyPipelineLayout(device, self.pipelinelayout, allocationcallbacks);
    c.vkDestroyPipeline(device, self.defaultpipeline, allocationcallbacks);
}
