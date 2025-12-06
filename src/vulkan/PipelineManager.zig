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
staticlayout: c.VkDescriptorSetLayout,
dynamiclayout: c.VkDescriptorSetLayout,
defaultpipeline: c.VkPipeline,

pub fn init(allocator: std.mem.Allocator, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) Self {
    var staticlayout: c.VkDescriptorSetLayout = undefined;
    var dynamiclayout: c.VkDescriptorSetLayout = undefined;
    {
        var builder: DescriptorLayoutBuilder = .init();
        defer builder.deinit(allocator);
        builder.addBinding(allocator, 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        dynamiclayout = builder.build(
            device,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    {
        var builder: DescriptorLayoutBuilder = .init();
        defer builder.deinit(allocator);
        builder.addBinding(allocator, 0, c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
        builder.addBinding(allocator, 1, c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
        staticlayout = builder.build(
            device,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    const descriptorlayouts: [2]c.VkDescriptorSetLayout = .{ dynamiclayout, staticlayout };
    const layoutinfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &descriptorlayouts,
        .pushConstantRangeCount = 0,
    };

    var pipelinelayout: c.VkPipelineLayout = undefined;
    checkVkPanic(c.vkCreatePipelineLayout(device, &layoutinfo, null, &pipelinelayout));
    const pipeline = defaultpipline.init(device, pipelinelayout, allocationcallbacks);

    return .{
        .defaultpipeline = pipeline,
        .pipelinelayout = pipelinelayout,
        .dynamiclayout = dynamiclayout,
        .staticlayout = staticlayout,
    };
}

pub fn deinit(self: *Self, device: c.VkDevice, allocationcallbacks: ?*c.VkAllocationCallbacks) void {
    c.vkDestroyDescriptorSetLayout(device, self.staticlayout, allocationcallbacks);
    c.vkDestroyDescriptorSetLayout(device, self.dynamiclayout, allocationcallbacks);
    c.vkDestroyPipelineLayout(device, self.pipelinelayout, allocationcallbacks);
    c.vkDestroyPipeline(device, self.defaultpipeline, allocationcallbacks);
}
