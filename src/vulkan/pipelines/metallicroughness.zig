const c = @import("clibs");
const Vec4 = @import("linalg").Vec4(f32);
const Mat4x4 = @import("linalg").Mat4x4(f32);
const descriptors = @import("../descriptor.zig");
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
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
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

    const matrixrange = c.VkPushConstantRange{
        .offset = 0,
        .size = @sizeOf(common.ModelPushConstants),
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    };

    var layout_builder: descriptors.LayoutBuilder = descriptors.LayoutBuilder.init(engine.cpuallocator);
    defer layout_builder.deinit();
    layout_builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    layout_builder.add_binding(1, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
    layout_builder.add_binding(2, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

    engine.descriptorsetlayouts[4] = layout_builder.build(engine.device.handle, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, null, 0);

    const layouts = [_]c.VkDescriptorSetLayout{ engine.descriptorsetlayouts[2], engine.descriptorsetlayouts[4] };

    const mesh_layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &matrixrange,
    };

    var newlayout: c.VkPipelineLayout = undefined;

    debug.check_vk(c.vkCreatePipelineLayout(engine.device.handle, &mesh_layout_info, null, &newlayout)) catch @panic(
        "Failed to create pipeline layout",
    );

    engine.pipelinelayouts[1] = newlayout;

    var pipelineBuilder = PipelineBuilder.init(engine.cpuallocator);
    defer pipelineBuilder.deinit();
    pipelineBuilder.set_shaders(vertex_module, fragment_module);
    pipelineBuilder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipelineBuilder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.set_multisampling_none();
    pipelineBuilder.disable_blending();
    pipelineBuilder.enable_depthtest(true, c.VK_COMPARE_OP_LESS);
    // pipelineBuilder.disable_depthtest();

    pipelineBuilder.set_color_attachment_format(engine.formats[1]);
    pipelineBuilder.set_depth_format(engine.formats[2]);

    pipelineBuilder.pipeline_layout = newlayout;

    engine.pipelines[1] = pipelineBuilder.build_pipeline(engine.device.handle);

    pipelineBuilder.enable_blending_additive();
    pipelineBuilder.enable_depthtest(false, c.VK_COMPARE_OP_LESS);

    engine.pipelines[2] = pipelineBuilder.build_pipeline(engine.device.handle);
}

fn clear_resources(self: *@This(), device: c.VkDevice) void {
    c.vkDestroyDescriptorSetLayout(device, self.materiallayout, null);
    c.vkDestroyPipelineLayout(device, self.transparent_pipeline.layout, null);
    c.vkDestroyPipeline(device, self.transparent_pipeline.pipeline, null);
    c.vkDestroyPipeline(device, self.opaque_pipeline.pipeline, null);
}

pub fn draw(core: *Core, cmd: c.VkCommandBuffer) void {
    const frame_index = core.framecontext.current;
    var frame = &core.framecontext.frames[frame_index];
    const global_descriptor = frame.descriptors.allocate(core.device.handle, core.descriptorsetlayouts[1], null);
    {
        var writer = descriptors.Writer.init(core.cpuallocator);
        defer writer.deinit();
        writer.write_buffer(
            0,
            frame.allocatedbuffers.buffer,
            @sizeOf(common.SceneDataUniform),
            0,
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.update_set(core.device.handle, global_descriptor);
    }

    var time: f32 = @floatFromInt(core.framenumber);
    time /= 100;
    var view = Mat4x4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, time / 2.0);
    view = view.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, time);
    view = view.translate(.{ .x = 0.0, .y = 0.0, .z = 2.0 });
    const model = view;
    var push_constants: common.ModelPushConstants = .{
        .model = model,
        .vertex_buffer = core.meshassets.items[0].mesh_buffers.vertex_buffer_adress,
    };

    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, core.pipelines[1]);
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[1],
        0,
        1,
        &global_descriptor,
        0,
        null,
    );
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[1],
        1,
        1,
        &core.descriptorsets[2],
        0,
        null,
    );
    c.vkCmdPushConstants(
        cmd,
        core.pipelinelayouts[1],
        c.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(common.ModelPushConstants),
        &push_constants,
    );
    c.vkCmdBindIndexBuffer(cmd, core.meshassets.items[0].mesh_buffers.index_buffer.buffer, 0, c.VK_INDEX_TYPE_UINT32);
    const surface = core.meshassets.items[0].surfaces.items[0];
    c.vkCmdDrawIndexed(cmd, surface.count, 1, surface.start_index, 0, 0);
}
