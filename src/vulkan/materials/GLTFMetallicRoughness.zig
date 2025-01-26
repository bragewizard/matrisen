
const GLTFMetallicRoughness = struct {
    opaque_pipeline: t.MaterialPipeline = undefined,
    transparent_pipeline: t.MaterialPipeline = undefined,
    materiallayout: c.VkDescriptorSetLayout = undefined,
    writer: d.DescriptorWriter,

    const MaterialConstants = struct { colorfactors: m.Vec4, metalrough_factors: m.Vec4, padding: [14]m.Vec4 };

    const MaterialResources = struct { 
        colorimage: t.AllocatedImageAndView = undefined, 
        colorsampler: c.VkSampler = undefined, 
        metalroughimage: t.AllocatedImageAndView = undefined, 
        metalroughsampler: c.VkSampler = undefined, 
        databuffer: c.VkBuffer = undefined, 
        databuffer_offset: u32 = undefined, 
    };

    pub fn init(alloc:std.mem.Allocator) @This() {
        return .{
            .writer = d.DescriptorWriter.init(alloc)  
        };
    }

    pub fn build_pipelines(self: *@This(), engine: *Self) void {

        const vertex_code align(4) = @embedFile("mesh.vert").*;
        const fragment_code align(4) = @embedFile("mesh.frag").*;

        const vertex_module = vki.create_shader_module(engine.device, &vertex_code, vk_alloc_cbs) orelse null;
        const fragment_module = vki.create_shader_module(engine.device, &fragment_code, vk_alloc_cbs) orelse null;
        if (vertex_module != null) log.info("Created vertex shader module", .{});
        if (fragment_module != null) log.info("Created fragment shader module", .{});

        defer c.vkDestroyShaderModule(engine.device, vertex_module, vk_alloc_cbs);
        defer c.vkDestroyShaderModule(engine.device, fragment_module, vk_alloc_cbs);

        const matrixrange = c.VkPushConstantRange{
            .offset = 0,
            .size = @sizeOf(t.GPUDrawPushConstants),
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT
        };

        var layout_builder = d.DescriptorLayoutBuilder{};
        layout_builder.init(engine.cpu_allocator);
        defer layout_builder.deinit();
        layout_builder.add_binding(0, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        layout_builder.add_binding(1, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        layout_builder.add_binding(2, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

        self.materiallayout = layout_builder.build(engine.device, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, null,0);

        const layouts = [_]c.VkDescriptorSetLayout{ engine.gpu_scene_data_descriptor_layout, self.materiallayout };

        const mesh_layout_info = c.VkPipelineLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .flags = 0,
            .setLayoutCount = 2,
            .pSetLayouts = &layouts,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &matrixrange,
        };

        var newlayout: c.VkPipelineLayout = undefined;

        check_vk(c.vkCreatePipelineLayout(engine.device, &mesh_layout_info, null, &newlayout)) catch @panic("Failed to create pipeline layout");

        self.opaque_pipeline.layout = newlayout;
        self.transparent_pipeline.layout = newlayout;

        var pipelineBuilder = PipelineBuilder.init(engine.cpu_allocator);
        defer pipelineBuilder.deinit();
        pipelineBuilder.set_shaders(vertex_module, fragment_module);
        pipelineBuilder.set_input_topology(c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
        pipelineBuilder.set_polygon_mode(c.VK_POLYGON_MODE_FILL);
        pipelineBuilder.set_cull_mode(c.VK_CULL_MODE_NONE, c.VK_FRONT_FACE_CLOCKWISE);
        pipelineBuilder.set_multisampling_none();
        pipelineBuilder.disable_blending();
        pipelineBuilder.enable_depthtest(true, c.VK_COMPARE_OP_GREATER_OR_EQUAL);

        pipelineBuilder.set_color_attachment_format(engine.draw_image_format);
        pipelineBuilder.set_depth_format(engine.depth_image_format);

        pipelineBuilder.pipeline_layout = newlayout;

        self.opaque_pipeline.pipeline = pipelineBuilder.build_pipeline(engine.device);

        pipelineBuilder.enable_blending_additive();
        pipelineBuilder.enable_depthtest(false, c.VK_COMPARE_OP_GREATER_OR_EQUAL);

        self.transparent_pipeline.pipeline = pipelineBuilder.build_pipeline(engine.device);
    }

    fn clear_resources(self: *@This(), device: c.VkDevice) void {
        c.vkDestroyDescriptorSetLayout(device,self.materiallayout ,null );
        c.vkDestroyPipelineLayout(device,self.transparent_pipeline.layout ,null );
        c.vkDestroyPipeline(device,self.transparent_pipeline.pipeline ,null );
        c.vkDestroyPipeline(device,self.opaque_pipeline.pipeline ,null );
        self.writer.deinit();
    }

    fn write_material(self: *@This(), device: c.VkDevice, pass: t.MaterialPass, resources: MaterialResources, descriptor_allocator: *d.DescriptorAllocatorGrowable) t.MaterialInstance {
        var matdata = t.MaterialInstance{};
        matdata.passtype = pass;
        if (pass == t.MaterialPass.Transparent) {
        matdata.pipeline = &self.transparent_pipeline;
        }
        else {
        matdata.pipeline = &self.opaque_pipeline;
        }

        matdata.materialset = descriptor_allocator.allocate(device, self.materiallayout, null);


        self.writer.clear();
        self.writer.write_buffer(0, resources.databuffer, @sizeOf(MaterialConstants), resources.databuffer_offset, c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        self.writer.write_image(1, resources.colorimage.view, resources.colorsampler, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.writer.write_image(2, resources.metalroughimage.view, resources.metalroughsampler, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);

        self.writer.update_set(device, matdata.materialset);

        return matdata;
    }
};
