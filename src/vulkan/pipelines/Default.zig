const std = @import("std");
const c = @import("../../clibs.zig").libs;
const check_vk_panic = @import("../debug.zig").check_vk_panic;
const descriptor = @import("../descriptor.zig");
const vk_alloc_cbs = Core.vkallocationcallbacks;
const buffer = @import("../buffer.zig");
const linalg = @import("../../linalg");
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const PipelineBuilder = @import("../pipeline.zig");
const FrameContext = @import("../command.zig").FrameContext;
const Core = @import("../core.zig");
const Mat4x4 = linalg.Mat4x4(f32);

layout: c.VkPipelineLayout = undefined,
pipeline: c.VkPipeline = undefined,
resourcelayout: c.VkDescriptorSetLayout = undefined,
scenedatalayout: c.VkDescriptorSetLayout = undefined,
static_set: c.VkDescriptorSet = undefined,
dynamic_sets: [Core.multibuffering]c.VkDescriptorSet = undefined,

const Self = @This();

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

pub fn init(self: *Self, core: *Core) void {
    {
        var builder: descriptor.LayoutBuilder = .init();
        defer builder.deinit(core.cpuallocator);
        builder.add_binding(core.cpuallocator, 0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        self.scenedatalayout = builder.build(
            core.device.handle,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    {
        var builder: descriptor.LayoutBuilder = .init();
        defer builder.deinit(core.cpuallocator);
        builder.add_binding(core.cpuallocator, 0, c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER);
        self.resourcelayout = builder.build(
            core.device.handle,
            c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    const vertex_code align(4) = @embedFile("default.vert.glsl").*;
    const fragment_code align(4) = @embedFile("default.frag.glsl").*;

    const vertex_module = PipelineBuilder.createShaderModule(
        core.device.handle,
        &vertex_code,
        vk_alloc_cbs,
    ) orelse null;
    const fragment_module = PipelineBuilder.createShaderModule(
        core.device.handle,
        &fragment_code,
        vk_alloc_cbs,
    ) orelse null;
    if (vertex_module != null) std.log.info("Created vertex shader module", .{});
    if (fragment_module != null) std.log.info("Created fragment shader module", .{});

    defer c.vkDestroyShaderModule(core.device.handle, vertex_module, vk_alloc_cbs);
    defer c.vkDestroyShaderModule(core.device.handle, fragment_module, vk_alloc_cbs);

    const layouts = [_]c.VkDescriptorSetLayout{ self.scenedatalayout, self.resourcelayout };

    const mesh_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 0,
    };

    var newlayout: c.VkPipelineLayout = undefined;

    check_vk_panic(c.vkCreatePipelineLayout(core.device.handle, &mesh_layout_info, null, &newlayout));

    self.layout = newlayout;

    const vertex: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertex_module,
        .pName = "main",
    };
    const fragment: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_module,
        .pName = "main",
    };

    var shaders: [2]c.VkPipelineShaderStageCreateInfo = .{ vertex, fragment };
    var pipelineBuilder: PipelineBuilder = .init();
    pipelineBuilder.shader_stages = &shaders;
    pipelineBuilder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipelineBuilder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.setMultisampling4();
    pipelineBuilder.disable_blending();
    pipelineBuilder.enable_depthtest(true, c.VK_COMPARE_OP_LESS);

    pipelineBuilder.set_color_attachment_format(core.renderattachmentformat);
    pipelineBuilder.set_depth_format(core.depth_format);

    pipelineBuilder.pipeline_layout = newlayout;
    self.pipeline = pipelineBuilder.buildPipeline(core.device.handle);

    pipelineBuilder.enable_blending_additive();
    pipelineBuilder.enable_depthtest(false, c.VK_COMPARE_OP_LESS);
    // self.transparent = pipelineBuilder.build_pipeline(core.device.handle);

}

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
