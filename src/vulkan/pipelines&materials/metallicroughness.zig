const c = @import("../../clibs.zig");
const m = @import("../../3Dmath.zig");
const descriptors = @import("../descriptors.zig");
const image = @import("../image.zig");
const std = @import("std");
const Core = @import("../core.zig");
const create_shader_module = @import("pipelinebuilder.zig").create_shader_module;
const debug = @import("../debug.zig");
const PipelineBuilder = @import("pipelinebuilder.zig");
const vk_alloc_cbs = @import("../core.zig").vkallocationcallbacks;
const log = std.log.scoped(.metalrough);
const common = @import("common.zig");

pub const MaterialConstantsUniform = extern struct {
    colorfactors: m.Vec4,
    metalrough_factors: m.Vec4,
    padding: [14]m.Vec4,
};

pub const MaterialResources = struct {
    colorimageview: c.VkImageView = undefined,
    colorsampler: c.VkSampler = undefined,
    metalroughimageview: c.VkImageView = undefined,
    metalroughsampler: c.VkSampler = undefined,
    databuffer: c.VkBuffer = undefined,
    databuffer_offset: u32 = undefined,
};

pub fn build_pipelines(engine: *Core) void {
    const vertex_code align(4) = @embedFile("mesh.vert.glsl").*;
    const fragment_code align(4) = @embedFile("mesh.frag.glsl").*;

    const vertex_module = create_shader_module(engine.device.handle, &vertex_code, vk_alloc_cbs) orelse null;
    const fragment_module = create_shader_module(engine.device.handle, &fragment_code, vk_alloc_cbs) orelse null;
    if (vertex_module != null) log.info("Created vertex shader module", .{});
    if (fragment_module != null) log.info("Created fragment shader module", .{});

    defer c.vkDestroyShaderModule(engine.device.handle, vertex_module, vk_alloc_cbs);
    defer c.vkDestroyShaderModule(engine.device.handle, fragment_module, vk_alloc_cbs);

    const matrixrange = c.VkPushConstantRange{ .offset = 0, .size = @sizeOf(common.ModelPushConstants), .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT };

    var layout_builder: descriptors.LayoutBuilder = descriptors.LayoutBuilder.init(engine.cpuallocator);
    defer layout_builder.deinit();
    layout_builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    layout_builder.add_binding(1, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
    layout_builder.add_binding(2, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

    engine.descriptorsetlayouts[3] = layout_builder.build(engine.device.handle, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, null, 0);

    const layouts = [_]c.VkDescriptorSetLayout{ engine.descriptorsetlayouts[1], engine.descriptorsetlayouts[3] };

    const mesh_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &matrixrange,
    };

    var newlayout: c.VkPipelineLayout = undefined;

    debug.check_vk(c.vkCreatePipelineLayout(engine.device.handle, &mesh_layout_info, null, &newlayout)) catch @panic("Failed to create pipeline layout");

    engine.pipelinelayouts[1] = newlayout;

    var pipelineBuilder = PipelineBuilder.init(engine.cpuallocator);
    defer pipelineBuilder.deinit();
    pipelineBuilder.set_shaders(vertex_module, fragment_module);
    pipelineBuilder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipelineBuilder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.set_multisampling_none();
    pipelineBuilder.disable_blending();
    pipelineBuilder.enable_depthtest(true, c.VK_COMPARE_OP_GREATER_OR_EQUAL);
    // pipelineBuilder.disable_depthtest();

    pipelineBuilder.set_color_attachment_format(engine.formats[1]);
    pipelineBuilder.set_depth_format(engine.formats[2]);

    pipelineBuilder.pipeline_layout = newlayout;

    engine.pipelines[1] = pipelineBuilder.build_pipeline(engine.device.handle);

    pipelineBuilder.enable_blending_additive();
    pipelineBuilder.enable_depthtest(false, c.VK_COMPARE_OP_GREATER_OR_EQUAL);

    engine.pipelines[2] = pipelineBuilder.build_pipeline(engine.device.handle);
}

fn clear_resources(self: *@This(), device: c.VkDevice) void {
    c.vkDestroyDescriptorSetLayout(device, self.materiallayout, null);
    c.vkDestroyPipelineLayout(device, self.transparent_pipeline.layout, null);
    c.vkDestroyPipeline(device, self.transparent_pipeline.pipeline, null);
    c.vkDestroyPipeline(device, self.opaque_pipeline.pipeline, null);
}
