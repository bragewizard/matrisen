const Core = @import("../core.zig");
const create_shader_module = @import("pipelinebuilder.zig").create_shader_module;
const check_vk = @import("../debug.zig").check_vk;
const PipelineBuilder = @import("pipelinebuilder.zig");
const vk_alloc_cbs = @import("../core.zig").vk_alloc_cbs;
const std = @import("std");
const log = std.log.scoped(.meshshader);
const c = @import("../../clibs.zig");

pub fn init_mesh_pipeline(core: *Core) void {
    const mesh_code align(4) = @embedFile("simple.mesh").*;
    const fragment_code align(4) = @embedFile("simple.frag").*;

    const mesh_module = create_shader_module(core, &mesh_code, vk_alloc_cbs) orelse null;
    const fragment_module = create_shader_module(core, &fragment_code, vk_alloc_cbs) orelse null;
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

    const shader_stages: [2]c.VkPipelineShaderStageCreateInfo = .{ stage_mesh, stage_frag };
    const color_format: c.VkFormat = core.swapchain.format;
    const rendering_info: c.VkPipelineRenderingCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &color_format,
    };

    const rasterstate: c.VkPipelineRasterizationStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_NONE,
        .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0,
    };

    const viewport_state: c.VkPipelineViewportStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const pipeline_layout_info: c.VkPipelineLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };

    var mesh_pipeline_layout: c.VkPipelineLayout = undefined;
    check_vk(c.vkCreatePipelineLayout(core.device.handle, &pipeline_layout_info, null, &mesh_pipeline_layout)) catch @panic("Failed to create pipeline layout");

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
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
    };
    const color_blending: c.VkPipelineColorBlendStateCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
    };

    // const input_assembly: c.VkPipelineInputAssemblyStateCreateInfo = .{
    //     .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    //     .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    //     .primitiveRestartEnable = c.VK_FALSE,
    // };

    // const vertex_input_info: c.VkPipelineVertexInputStateCreateInfo = .{
    //     .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    // };

    var pipeline_info: c.VkGraphicsPipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &rendering_info,
        .stageCount = @as(u32, @intCast(shader_stages.len)),
        .pStages = &shader_stages,
        .pRasterizationState = &rasterstate,
        .layout = mesh_pipeline_layout,
        .pViewportState = &viewport_state,
        .pColorBlendState = &color_blending,
        .pMultisampleState = &multisample,
        // .pInputAssemblyState = &input_assembly,
        // .pVertexInputState = &vertex_input_info,
    };

    const dynamic_state: [2]c.VkDynamicState = .{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state_info = std.mem.zeroInit(c.VkPipelineDynamicStateCreateInfo, .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = dynamic_state.len, .pDynamicStates = &dynamic_state[0] });

    pipeline_info.pDynamicState = &dynamic_state_info;

    var pipeline: c.VkPipeline = undefined;
    check_vk(c.vkCreateGraphicsPipelines(core.device.handle, null, 1, &pipeline_info, null, &pipeline)) catch @panic("failed to create meshpipeline");
    c.vkDestroyShaderModule(core.device.handle, mesh_module, vk_alloc_cbs);
    c.vkDestroyShaderModule(core.device.handle, fragment_module, vk_alloc_cbs);
    core.pipelines[0] = pipeline;
    core.pipeline_layouts[0] = mesh_pipeline_layout;
}
