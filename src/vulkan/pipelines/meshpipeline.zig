fn init_mesh_pipeline(self: *Self) void {
    const vertex_code align(4) = @embedFile("triangle_mesh.vert").*;
    const fragment_code align(4) = @embedFile("triangle.frag").*;
    // const fragment_code align(4) = @embedFile("tex_image.frag").*;

    const vertex_module = vki.create_shader_module(self.device, &vertex_code, vk_alloc_cbs) orelse null;
    const fragment_module = vki.create_shader_module(self.device, &fragment_code, vk_alloc_cbs) orelse null;
    if (vertex_module != null) log.info("Created vertex shader module", .{});
    if (fragment_module != null) log.info("Created fragment shader module", .{});
    const buffer_range = std.mem.zeroInit(c.VkPushConstantRange, .{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = @sizeOf(t.GPUDrawPushConstants),
    });
    const pipeline_layout_info = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &buffer_range,
        .pSetLayouts = &self.single_image_descriptor_layout,
        .setLayoutCount = 1,
    });

    check_vk(c.vkCreatePipelineLayout(self.device, &pipeline_layout_info, null, &self.mesh_pipeline_layout)) catch @panic("Failed to create pipeline layout");
    var pipeline_builder = PipelineBuilder.init(self.cpu_allocator);
    defer pipeline_builder.deinit();
    pipeline_builder.pipeline_layout = self.mesh_pipeline_layout;
    pipeline_builder.set_shaders(vertex_module, fragment_module);
    pipeline_builder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    pipeline_builder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
    pipeline_builder.set_cull_mode(c.VK_CULL_MODE_BACK_BIT, c.VK_FRONT_FACE_CLOCKWISE);
    pipeline_builder.set_multisampling_none();
    pipeline_builder.disable_blending();
    // pipeline_builder.enable_blending_additive();
    // pipeline_builder.enable_blending_alpha();
    // pipeline_builder.disable_depthtest();
    pipeline_builder.enable_depthtest(true, c.VK_COMPARE_OP_GREATER_OR_EQUAL);
    pipeline_builder.set_color_attachment_format(self.draw_image_format);
    pipeline_builder.set_depth_format(self.depth_image_format);
    self.mesh_pipeline = pipeline_builder.build_pipeline(self.device);
    c.vkDestroyShaderModule(self.device, vertex_module, vk_alloc_cbs);
    c.vkDestroyShaderModule(self.device, fragment_module, vk_alloc_cbs);
    self.pipeline_deletion_queue.push(self.mesh_pipeline);
    self.pipeline_layout_deletion_queue.push(self.mesh_pipeline_layout);
}
