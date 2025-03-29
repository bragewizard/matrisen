
    {
        var builder: DescriptorLayoutBuilder = .init(core.cpuallocator);
        defer builder.deinit();
        builder.add_binding(0, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
        pipelines.descriptors[5].layout = builder.build(
            core.device.handle,
            vk.VK_SHADER_STAGE_COMPUTE_BIT,
            null,
            0,
        );
    }


    pipelines.descriptors[5].sets[0] = core.globaldescriptorallocator.allocate(
        core.device.handle,
        pipelines.descriptors[5].layout,
        null,
    );

    {
        var writer: Pipelines.Writer = .init(core.cpuallocator);
        defer writer.deinit();
        writer.write_image(
            0,
            core.images.views[0],
            null,
            vk.VK_IMAGE_LAYOUT_GENERAL,
            vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        );
        writer.update_set(core.device.handle, pipelines.descriptors[5].sets[0]);
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
