const std = @import("std");
const c = @import("clibs");
const vk = @import("vulkan");
const geometry = @import("geometry");
const pipelines = @import("../pipelines.zig");
const buffers = @import("../buffers.zig");
const check_vk_panic = @import("../debug.zig").check_vk_panic;
const check_vk = @import("../debug.zig").check_vk;
const FrameContext = @import("../commands.zig").FrameContext;
const DescriptorLayoutBuilder = pipelines.DescriptorLayoutBuilder;
const Core = @import("../core.zig");
const vk_alloc_cbs = Core.vkallocationcallbacks;
const Mat4x4 = geometry.Mat4x4(f32);
const Vec4 = geometry.Vec4(f32);

pub const SceneDataUniform = extern struct {
    view: Mat4x4,
    proj: Mat4x4,
    viewproj: Mat4x4,
    ambient_color: Vec4,
    sunlight_dir: Vec4,
    sunlight_color: Vec4,
};

pub const ModelPushConstants = extern struct {
    model: Mat4x4,
    vertex_buffer: vk.VkDeviceAddress,
};

pub const MaterialConstantsUniform = extern struct {
    colorfactors: Vec4,
    metalrough_factors: Vec4,
    padding: [14]Vec4,
};

pub const MaterialResources = struct {
    colorimageview: vk.VkImageView = undefined,
    colorsampler: vk.VkSampler = undefined,
    metalroughimageview: vk.VkImageView = undefined,
    metalroughsampler: vk.VkSampler = undefined,
    databuffer: vk.VkBuffer = undefined,
    databuffer_offset: u32 = undefined,
};

pub const MaterialPass = enum { MainColor, Transparent, Other };

pub fn setSceneData(core: *Core, frame: *FrameContext) void {
    frame.allocatedbuffers = buffers.create(
        core,
        @sizeOf(SceneDataUniform),
        .uniform_buffer_bit,
        c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );
    var scene_uniform_data: *SceneDataUniform = @alignCast(@ptrCast(frame.allocatedbuffers.info.pMappedData.?));
    scene_uniform_data.view = core.camera.view();
    scene_uniform_data.proj = Mat4x4.perspective(
        std.math.degreesToRadians(60.0),
        @as(f32, @floatFromInt(frame.draw_extent.width)) / @as(f32, @floatFromInt(frame.draw_extent.height)),
        0.1,
        1000.0,
    );
    scene_uniform_data.viewproj = Mat4x4.mul(scene_uniform_data.proj, scene_uniform_data.view);
    scene_uniform_data.sunlight_dir = .{ .x = 0.1, .y = 0.1, .z = 1, .w = 1 };
    scene_uniform_data.sunlight_color = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    scene_uniform_data.ambient_color = .{ .x = 1, .y = 0.6, .z = 0, .w = 1 };
}

pub fn descriptorLayouts(self: *@This(), core: *Core) void {
    {
        var builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, .uniform_buffer);
        self.vert_scenedata_layout = builder.build(
            core.device.handle,
            .vertex_bit | .fragment_bit,
            null,
            0,
        );
    }
    {
        var builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, .uniform_buffer);
        self.mesh_scenedata_layout = builder.build(
            core.device.handle,
            .mesh_bit_ext | .fragment_bit,
            null,
            0,
        );
    }
    {
        var layout_builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer layout_builder.deinit();
        layout_builder.add_binding(0, vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        layout_builder.add_binding(1, vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        layout_builder.add_binding(2, vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

        self.vert_materialdata_layout = layout_builder.build(
            core.device.handle,
            vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    {
        var layout_builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer layout_builder.deinit();
        layout_builder.add_binding(0, .uniform_buffer);
        layout_builder.add_binding(1, .combined_image_sampler);
        layout_builder.add_binding(2, .combined_image_sampler);

        self.mesh_materialdata_layout = layout_builder.build(
            core.device.handle,
            vk.VK_SHADER_STAGE_MESH_BIT_EXT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
            null,
            0,
        );
    }
    {
        var builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.combolayout = builder.build(core.device.handle, vk.VK_SHADER_STAGE_FRAGMENT_BIT, null, 0);
    }
    {
        var builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
        self.computeimagelayout = builder.build(core.device.handle, vk.VK_SHADER_STAGE_COMPUTE_BIT, null, 0);
    }
}

pub fn writeDescriptorsets(self: *@This(), core: *Core) void {
    var sizes = [_]pipelines.Allocator.PoolSizeRatio{
        .{ .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
        .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
    };
    self.globaldescriptorallocator.init(self.device.handle, 10, &sizes, self.cpuallocator);

    core.allocatedbuffers[0] = buffers.create(
        core,
        @sizeOf(MaterialConstantsUniform),
        vk.BufferUsageFlags.uniform_buffer_bit,
        vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    );

    var materialuniformdata = @as(
        *MaterialConstantsUniform,
        @alignCast(@ptrCast(core.allocatedbuffers[0].info.pMappedData.?)),
    );
    materialuniformdata.colorfactors = Vec4{ .x = 1, .y = 1, .z = 1, .w = 1 };
    materialuniformdata.metalrough_factors = Vec4{ .x = 1, .y = 0.5, .z = 1, .w = 1 };

    self.mesh_scenedata[0] = core.globaldescriptorallocator.allocate(
        core.device.handle,
        self.mesh_scenedata_layout,
        null,
    );
    self.vert_scenedata[0] = core.globaldescriptorallocator.allocate(
        core.device.handle,
        self.vert_scenedata_layout,
        null,
    );
    // self.computeimage[0] = core.globaldescriptorallocator.allocate(
    //     core.device.handle,
    //     self.computeimagelayout,
    //     null,
    // );
    {
        var writer: pipelines.Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.clear();
        writer.write_buffer(
            0,
            core.allocatedbuffers[0].buffer,
            @sizeOf(MaterialConstantsUniform),
            0,
            .uniform_buffer,
        );
        writer.write_image(
            1,
            core.imageviews[2],
            core.samplers[0],
            .shader_read_only_optimal,
            .combined_image_sampler,
        );
        writer.write_image(
            2,
            core.imageviews[2],
            core.samplers[0],
            .shader_read_only_optimal,
            .combined_image_sampler,
        );
        writer.update_set(core.device.handle, self.mesh_scenedata[0]);
        writer.update_set(core.device.handle, self.vert_scenedata[0]);
    }
    // {
    //     var writer: descriptor.Writer = .init(core.cpuallocator);
    //     defer writer.deinit();
    //     writer.write_image(
    //         0,
    //         core.imageviews[0],
    //         null,
    //         vk.VK_IMAGE_LAYOUT_GENERAL,
    //         vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    //     );
    //     writer.update_set(core.device.handle, self.computeimage[0]);
    // }
}

pub fn build_pipeline(core: *Core) void {
    const mesh_code align(4) = @embedFile("simple.mesh.glsl").*;
    const fragment_code align(4) = @embedFile("simple.frag.glsl").*;

    const mesh_module = pipelines.create_shader_module(core.device.handle, &mesh_code, vk_alloc_cbs) orelse null;
    const fragment_module = pipelines.create_shader_module(core.device.handle, &fragment_code, vk_alloc_cbs) orelse null;
    if (mesh_module != null) std.log.info("Created mesh shader module", .{});
    if (fragment_module != null) std.log.info("Created fragment shader module", .{});

    const stage_mesh: vk.VkPipelineShaderStageCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .module = mesh_module,
        .pName = "main",
    };

    const stage_frag: vk.VkPipelineShaderStageCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_module,
        .pName = "main",
    };

    const matrixrange = vk.VkPushConstantRange{
        .offset = 0,
        .size = @sizeOf(ModelPushConstants),
        .stageFlags = vk.VK_SHADER_STAGE_MESH_BIT_EXT,
    };
    const layouts = [_]vk.VkDescriptorSetLayout{ core.descriptorsetlayouts[4], core.descriptorsetlayouts[5] };

    const shader_stages: [2]vk.VkPipelineShaderStageCreateInfo = .{ stage_mesh, stage_frag };
    const color_format: vk.VkFormat = core.formats[1];
    const depth_format: vk.VkFormat = core.formats[2];

    const rendering_info: vk.VkPipelineRenderingCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &color_format,
        .depthAttachmentFormat = depth_format,
    };

    const rasterstate: vk.VkPipelineRasterizationStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_NONE,
        .frontFace = vk.VK_FRONT_FACE_CLOCKWISE,
        .lineWidth = 1.0,
    };

    const depth_stencil: vk.VkPipelineDepthStencilStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = vk.VK_TRUE,
        .depthWriteEnable = vk.VK_TRUE,
        .depthCompareOp = vk.VK_COMPARE_OP_LESS,
        .depthBoundsTestEnable = vk.VK_FALSE,
        .stencilTestEnable = vk.VK_FALSE,
        .minDepthBounds = 0.0,
        .maxDepthBounds = 1.0,
        .front = .{},
        .back = .{},
    };

    const viewport_state: vk.VkPipelineViewportStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };

    const layout_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &matrixrange,
    };

    var pipeline_layout: vk.VkPipelineLayout = undefined;
    check_vk_panic(vk.vkCreatePipelineLayout(core.device.handle, &layout_info, null, &pipeline_layout));

    const multisample: vk.VkPipelineMultisampleStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = vk.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = vk.VK_FALSE,
        .alphaToOneEnable = vk.VK_FALSE,
    };

    const color_blend_attachment: vk.VkPipelineColorBlendAttachmentState = .{
        .blendEnable = vk.VK_FALSE,
        // .blendEnable = vk.VK_TRUE,
        // .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        // .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        // .colorBlendOp = vk.VK_BLEND_OP_ADD,
        // .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        // .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        // .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
    };
    const color_blending: vk.VkPipelineColorBlendStateCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .logicOpEnable = vk.VK_FALSE,
        .logicOp = vk.VK_LOGIC_OP_COPY,
    };

    var pipeline_info: vk.VkGraphicsPipelineCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
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

    const dynamic_state: [2]vk.VkDynamicState = .{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const dynamic_state_info: vk.VkPipelineDynamicStateCreateInfo = .{ .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO, .dynamicStateCount = dynamic_state.len, .pDynamicStates = &dynamic_state[0] };

    pipeline_info.pDynamicState = &dynamic_state_info;

    var pipeline: vk.VkPipeline = undefined;
    check_vk_panic(vk.vkCreateGraphicsPipelines(core.device.handle, null, 1, &pipeline_info, null, &pipeline));
    vk.vkDestroyShaderModule(core.device.handle, mesh_module, vk_alloc_cbs);
    vk.vkDestroyShaderModule(core.device.handle, fragment_module, vk_alloc_cbs);
    core.pipelines[0] = pipeline;
    core.pipelinelayouts[0] = pipeline_layout;
}

pub fn drawMesh(core: *Core, frame: *FrameContext) void {
    const cmd = frame.command_buffer;
    const global_descriptor = frame.descriptors.allocate(core.device.handle, core.descriptorsetlayouts[3], null);
    {
        var writer: pipelines.Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.write_buffer(
            0,
            frame.allocatedbuffers.buffer,
            @sizeOf(SceneDataUniform),
            0,
            vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.update_set(core.device.handle, global_descriptor);
    }

    const view = Mat4x4.identity;
    const model = view;
    var push_constants: ModelPushConstants = .{
        .model = model,
        .vertex_buffer = core.meshassets.items[0].mesh_buffers.vertex_buffer_adress,
    };

    vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, core.pipelines[0]);
    vk.vkCmdBindDescriptorSets(
        cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[0],
        0,
        1,
        &global_descriptor,
        0,
        null,
    );
    vk.vkCmdBindDescriptorSets(
        cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[0],
        1,
        1,
        &core.descriptorsets[2],
        0,
        null,
    );
    vk.vkCmdPushConstants(
        cmd,
        core.pipelinelayouts[0],
        vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        0,
        @sizeOf(ModelPushConstants),
        &push_constants,
    );
    core.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1);
}

pub fn build_pipelines(engine: *Core) void {
    const vertex_code align(4) = @embedFile("mesh.vert.glsl").*;
    const fragment_code align(4) = @embedFile("mesh.frag.glsl").*;

    const vertex_module = pipelines.create_shader_module(engine.device.handle, &vertex_code, vk_alloc_cbs) orelse null;
    const fragment_module = pipelines.create_shader_module(engine.device.handle, &fragment_code, vk_alloc_cbs) orelse null;
    if (vertex_module != null) std.log.info("Created vertex shader module", .{});
    if (fragment_module != null) std.log.info("Created fragment shader module", .{});

    defer vk.vkDestroyShaderModule(engine.device.handle, vertex_module, vk_alloc_cbs);
    defer vk.vkDestroyShaderModule(engine.device.handle, fragment_module, vk_alloc_cbs);

    const matrixrange = vk.VkPushConstantRange{
        .offset = 0,
        .size = @sizeOf(ModelPushConstants),
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT,
    };

    const layouts = [_]vk.VkDescriptorSetLayout{ engine.descriptorsetlayouts[2], engine.descriptorsetlayouts[4] };

    const mesh_layout_info = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = 0,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &matrixrange,
    };

    var newlayout: vk.VkPipelineLayout = undefined;

    check_vk_panic(vk.vkCreatePipelineLayout(engine.device.handle, &mesh_layout_info, null, &newlayout));

    engine.pipelinelayouts[1] = newlayout;

    var pipelineBuilder = pipelines.PipelineBuilder.init(engine.cpuallocator);
    defer pipelineBuilder.deinit();
    pipelineBuilder.set_shaders(vertex_module, fragment_module);
    pipelineBuilder.set_input_topology(vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipelineBuilder.set_polygon_mode(vk.VK_POLYGON_MODE_FILL);
    pipelineBuilder.set_cull_mode(vk.VK_CULL_MODE_NONE, vk.VK_FRONT_FACE_CLOCKWISE);
    pipelineBuilder.set_multisampling_none();
    pipelineBuilder.disable_blending();
    pipelineBuilder.enable_depthtest(true, vk.VK_COMPARE_OP_LESS);

    pipelineBuilder.set_color_attachment_format(engine.formats[1]);
    pipelineBuilder.set_depth_format(engine.formats[2]);

    pipelineBuilder.pipeline_layout = newlayout;

    engine.pipelines[1] = pipelineBuilder.build_pipeline(engine.device.handle);

    pipelineBuilder.enable_blending_additive();
    pipelineBuilder.enable_depthtest(false, vk.VK_COMPARE_OP_LESS);

    engine.pipelines[2] = pipelineBuilder.build_pipeline(engine.device.handle);
}

pub fn draw(core: *Core, frame: *FrameContext) void {
    const cmd = frame.command_buffer;
    const global_descriptor = frame.descriptors.allocate(core.device.handle, core.descriptorsetlayouts[1], null);
    {
        var writer = pipelines.Writer.init(core.cpuallocator);
        defer writer.deinit();
        writer.write_buffer(
            0,
            frame.allocatedbuffers.buffer,
            @sizeOf(SceneDataUniform),
            0,
            vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        );
        writer.update_set(core.device.handle, global_descriptor);
    }

    var time: f32 = @floatFromInt(core.framenumber);
    time /= 100;
    var view = Mat4x4.rotation(.{ .x = 1.0, .y = 0.0, .z = 0.0 }, time / 2.0);
    view = view.rotate(.{ .x = 0.0, .y = 1.0, .z = 0.0 }, time);
    view = view.translate(.{ .x = 0.0, .y = 0.0, .z = 2.0 });
    const model = view;
    var push_constants: ModelPushConstants = .{
        .model = model,
        .vertex_buffer = core.meshassets.items[0].mesh_buffers.vertex_buffer_adress,
    };

    vk.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, core.pipelines[1]);
    vk.vkCmdBindDescriptorSets(
        cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[1],
        0,
        1,
        &global_descriptor,
        0,
        null,
    );
    vk.vkCmdBindDescriptorSets(
        cmd,
        vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        core.pipelinelayouts[1],
        1,
        1,
        &core.descriptorsets[2],
        0,
        null,
    );
    vk.vkCmdPushConstants(
        cmd,
        core.pipelinelayouts[1],
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(ModelPushConstants),
        &push_constants,
    );
    vk.vkCmdBindIndexBuffer(cmd, core.meshassets.items[0].mesh_buffers.index_buffer.buffer, 0, vk.VK_INDEX_TYPE_UINT32);
    const surface = core.meshassets.items[0].surfaces.items[0];
    vk.vkCmdDrawIndexed(cmd, surface.count, 1, surface.start_index, 0, 0);
}

// fn init_background_pipelines(self: *Self) void {
//     var compute_layout = std.mem.zeroInit(vk.VkPipelineLayoutCreateInfo, .{
//         .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
//         .setLayoutCount = 1,
//         .pSetLayouts = &self.draw_image_descriptor_layout,
//     });

//     const push_constant_range = std.mem.zeroInit(vk.VkPushConstantRange, .{
//         .stageFlags = vk.VK_SHADER_STAGE_COMPUTE_BIT,
//         .offset = 0,
//         .size = @sizeOf(t.ComputePushConstants),
//     });

//     compute_layout.pPushConstantRanges = &push_constant_range;
//     compute_layout.pushConstantRangeCount = 1;

//     check_vk(vk.vkCreatePipelineLayout(self.device, &compute_layout, null, &self.gradient_pipeline_layout));

//     const comp_code align(4) = @embedFile("gradient.comp").*;
//     const comp_module = vki.create_shader_module(self.device, &comp_code, vk_alloc_cbs) orelse null;
//     if (comp_module != null) log.info("Created compute shader module", .{});

//     const stage_ci = std.mem.zeroInit(vk.VkPipelineShaderStageCreateInfo, .{
//         .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
//         .stage = vk.VK_SHADER_STAGE_COMPUTE_BIT,
//         .module = comp_module,
//         .pName = "main",
//     });

//     const compute_ci = std.mem.zeroInit(vk.VkComputePipelineCreateInfo, .{
//         .sType = vk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
//         .layout = self.gradient_pipeline_layout,
//         .stage = stage_ci,
//     });

//     check_vk(vk.vkCreateComputePipelines(self.device, null, 1, &compute_ci, null, &self.gradient_pipeline));
//     vk.vkDestroyShaderModule(self.device, comp_module, vk_alloc_cbs);
//     self.pipeline_deletion_queue.push(self.gradient_pipeline);
//     self.pipeline_layout_deletion_queue.push(self.gradient_pipeline_layout);
// }
