const std = @import("std");
const c = @import("../../clibs/clibs.zig").libs;
const check_vk_panic = @import("../debug.zig").check_vk_panic;
const buffer = @import("../buffer.zig");
const linalg = @import("../../linalg");
const Vec3 = linalg.Vec3(f32);
const Vec4 = linalg.Vec4(f32);
const PipelineBuilder = @import("../PipelineManager.zig");
const FrameContext = @import("../FrameContext.zig");
const Core = @import("../Core.zig");
const Mat4x4 = linalg.Mat4x4(f32);

pub const MaterialConstantsUniform = extern struct {
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
};

pub fn init(core: *Core) c.VkPipeline {
    const vertex_code align(4) = @embedFile("default.vert.glsl").*;
    const fragment_code align(4) = @embedFile("default.frag.glsl").*;

    const vertex_module = PipelineBuilder.createShaderModule(
        core.device.handle,
        &vertex_code,
        core.vkallocationcallbacks,
    ) orelse null;
    const fragment_module = PipelineBuilder.createShaderModule(
        core.device.handle,
        &fragment_code,
        core.vkallocationcallbacks,
    ) orelse null;
    if (vertex_module != null) std.log.info("Created vertex shader module", .{});
    if (fragment_module != null) std.log.info("Created fragment shader module", .{});

    defer c.vkDestroyShaderModule(core.device.handle, vertex_module, core.vkallocationcallbacks);
    defer c.vkDestroyShaderModule(core.device.handle, fragment_module, core.vkallocationcallbacks);

    const layouts = [_]c.VkDescriptorSetLayout{ core.scenedatalayout, core.resourcelayout };

    const mesh_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 0,
    };

    var newlayout: c.VkPipelineLayout = undefined;

    check_vk_panic(c.vkCreatePipelineLayout(core.device.handle, &mesh_layout_info, null, &newlayout));

    core.defaultpipelinelayout = newlayout;

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
    const pipeline = pipelineBuilder.buildPipeline(core.device.handle);

    pipelineBuilder.enable_blending_additive();
    pipelineBuilder.enable_depthtest(false, c.VK_COMPARE_OP_LESS);
    // const transparent = pipelineBuilder.build_pipeline(core.device.handle);
    return pipeline;
}
