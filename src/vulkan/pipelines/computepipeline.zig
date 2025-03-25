const c = @import("clibs");
const linalg = @import("linalg");
const Vec4 = linalg.Vec4(f32);

pub const ComputePushConstants = extern struct {
    data1: Vec4,
    data2: Vec4,
    data3: Vec4,
    data4: Vec4,
};

// fn init_background_pipelines(self: *Self) void {
//     var compute_layout = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
//         .setLayoutCount = 1,
//         .pSetLayouts = &self.draw_image_descriptor_layout,
//     });

//     const push_constant_range = std.mem.zeroInit(c.VkPushConstantRange, .{
//         .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
//         .offset = 0,
//         .size = @sizeOf(t.ComputePushConstants),
//     });

//     compute_layout.pPushConstantRanges = &push_constant_range;
//     compute_layout.pushConstantRangeCount = 1;

//     check_vk(c.vkCreatePipelineLayout(self.device, &compute_layout, null, &self.gradient_pipeline_layout)) catch @panic("Failed to create pipeline layout");

//     const comp_code align(4) = @embedFile("gradient.comp").*;
//     const comp_module = vki.create_shader_module(self.device, &comp_code, vk_alloc_cbs) orelse null;
//     if (comp_module != null) log.info("Created compute shader module", .{});

//     const stage_ci = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
//         .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
//         .module = comp_module,
//         .pName = "main",
//     });

//     const compute_ci = std.mem.zeroInit(c.VkComputePipelineCreateInfo, .{
//         .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
//         .layout = self.gradient_pipeline_layout,
//         .stage = stage_ci,
//     });

//     check_vk(c.vkCreateComputePipelines(self.device, null, 1, &compute_ci, null, &self.gradient_pipeline)) catch @panic("Failed to create compute pipeline");
//     c.vkDestroyShaderModule(self.device, comp_module, vk_alloc_cbs);
//     self.pipeline_deletion_queue.push(self.gradient_pipeline);
//     self.pipeline_layout_deletion_queue.push(self.gradient_pipeline_layout);
// }
