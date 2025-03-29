const Core = @import("../core.zig");
const create_shader_module = @import("pipelinebuilder.zig").create_shader_module;
const debug = @import("../debug.zig");
const PipelineBuilder = @import("pipelinebuilder.zig");
const vk_alloc_cbs = @import("../core.zig").vkallocationcallbacks;
const common = @import("common.zig");
const descriptors = @import("../descriptor.zig");
const std = @import("std");
const log = std.log.scoped(.meshshader);
const c = @import("clibs");
const Mat4x4 = @import("linalg").Mat4x4(f32);

pub fn build_pipeline(core: *Core) void {
    const mesh_code align(4) = @embedFile("simple.mesh.glsl").*;
    const fragment_code align(4) = @embedFile("simple.frag.glsl").*;

    const mesh_module = create_shader_module(core.device.handle, &mesh_code, vk_alloc_cbs) orelse null;
    const fragment_module = create_shader_module(core.device.handle, &fragment_code, vk_alloc_cbs) orelse null;
    if (mesh_module != null) log.info("Created mesh shader module", .{});
    if (fragment_module != null) log.info("Created fragment shader module", .{});

    const stage_mesh: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_MESH_BIT_EXT,
        .module = mesh_module,
        .pName = "main",
    };

    const stage_frag: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_module,
        .pName = "main",
    };

    var layout_builder: descriptors.LayoutBuilder = descriptors.LayoutBuilder.init(core.cpuallocator);
    defer layout_builder.deinit();
    layout_builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    layout_builder.add_binding(1, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
    layout_builder.add_binding(2, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

    core.descriptorsetlayouts[5] = layout_builder.build(
        core.device.handle,
        c.VK_SHADER_STAGE_MESH_BIT_EXT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
        null,
        0,
    );

    const matrixrange = c.VkPushConstantRange{
        .offset = 0,
        .size = @sizeOf(common.ModelPushConstants),
        .stageFlags = c.VK_SHADER_STAGE_MESH_BIT_EXT,
    };
    const layouts = [_]c.VkDescriptorSetLayout{ core.descriptorsetlayouts[4], core.descriptorsetlayouts[5] };

    const shader_stages: [2]c.VkPipelineShaderStageCreateInfo = .{ stage_mesh, stage_frag };
    const color_format: c.VkFormat = core.formats[1];
    const depth_format: c.VkFormat = core.formats[2];

    const rendering_info: c.VkPipelineRenderingCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &color_format,
        .depthAttachmentFormat = depth_format,
    };

    const rasterstate: c.VkPipelineRasterizationStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_NONE,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .lineWidth = 1.0,
    };

    const depth_stencil: c.VkPipelineDepthStencilStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = c.VK_TRUE,
        .depthWriteEnable = c.VK_TRUE,
        .depthCompareOp = c.VK_COMPARE_OP_LESS,
        .depthBoundsTestEnable = c.VK_FALSE,
        .stencilTestEnable = c.VK_FALSE,
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
        .front = .{},
        .back = .{},
    };

    const viewport_state: c.VkPipelineViewportStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const layout_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &matrixrange,
    };

    var pipeline_layout: c.VkPipelineLayout = undefined;
    debug.check_vk(c.vkCreatePipelineLayout(core.device.handle, &layout_info, null, &pipeline_layout)) catch @panic("Failed to create pipeline layout");

    const multisample: c.VkPipelineMultisampleStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    const color_blend_attachment: c.VkPipelineColorBlendAttachmentState = .{
        .blendEnable = c.VK_FALSE,
        // .blendEnable = c.VK_TRUE,
        // .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
        // .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        // .colorBlendOp = c.VK_BLEND_OP_ADD,
        // .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        // .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        // .alphaBlendOp = c.VK_BLEND_OP_ADD,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
    };
    const color_blending: c.VkPipelineColorBlendStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
    };

    var pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &rendering_info,
        .stageCount = @as(u32, @intCast(shader_stages.len)),
        .pStages = &shader_stages,
        .pRasterizationState = &rasterstate,
        .layout = pipeline_layout,
        .pViewportState = &viewport_state,
        .pColorBlendState = &color_blending,
        .pMultisampleState = &multisample,
        .pDepthStencilState = &depth_stencil,
    };

    const dynamic_state: [2]c.VkDynamicState = .{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state_info: c.VkPipelineDynamicStateCreateInfo = .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = dynamic_state.len, .pDynamicStates = &dynamic_state[0] };

    pipeline_info.pDynamicState = &dynamic_state_info;

    var pipeline: c.VkPipeline = undefined;
    debug.check_vk(c.vkCreateGraphicsPipelines(core.device.handle, null, 1, &pipeline_info, null, &pipeline)) catch @panic("failed to create meshpipeline");
    c.vkDestroyShaderModule(core.device.handle, mesh_module, vk_alloc_cbs);
    c.vkDestroyShaderModule(core.device.handle, fragment_module, vk_alloc_cbs);
    core.pipelines[0] = pipeline;
    core.pipelinelayouts[0] = pipeline_layout;
}

pub fn writeDescriptors() void {}


pub fn draw(core: *Core, cmd: c.VkCommandBuffer) void {
    const frame_index = core.framecontext.current;
    var frame = &core.framecontext.frames[frame_index];
    const global_descriptor = frame.descriptors.allocate(core.device.handle, core.descriptorsetlayouts[3], null);
    {
        var writer: descriptors.Writer = .init(core.cpuallocator);
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

    const view = Mat4x4.identity;
    const model = view;
    var push_constants: common.ModelPushConstants = .{
        .model = model,
        .vertex_buffer = core.meshassets.items[0].mesh_buffers.vertex_buffer_adress,
    };

    c.vkCmdBindPipeline(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, core.pipelines[0]);
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[0],
        0,
        1,
        &global_descriptor,
        0,
        null,
    );
    c.vkCmdBindDescriptorSets(
        cmd,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[0],
        1,
        1,
        &core.descriptorsets[2],
        0,
        null,
    );
    c.vkCmdPushConstants(
        cmd,
        core.pipelinelayouts[0],
        c.VK_SHADER_STAGE_MESH_BIT_EXT,
        0,
        @sizeOf(common.ModelPushConstants),
        &push_constants,
    );
    core.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1);
}
