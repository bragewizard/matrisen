const std = @import("std");
const c = @import("clibs");
const debug = @import("debug.zig");
const check_vk = debug.check_vk;
const check_vk_panic = debug.check_vk_panic;
const buffers = @import("buffers.zig");
const geometry = @import("geometry");
const images = @import("images.zig");
const Core = @import("core.zig");
const FrameContext = @import("commands.zig").FrameContexts.Context;

meshlayout: c.VkPipelineLayout = undefined,
vertlayout: c.VkPipelineLayout = undefined,

meshpipelines: [1]c.VkPipeline = undefined,
vertpipelines: [1]c.VkPipeline = undefined,

globaldescriptorallocator: Allocator = undefined,

mesh_scenedata_layout: c.VkDescriptorSetLayout = undefined,
vert_scenedata_layout: c.VkDescriptorSetLayout = undefined,
vert_materialdata_layout: c.VkDescriptorSetLayout = undefined,
mesh_materialdata_layout: c.VkDescriptorSetLayout = undefined,
combolayout: c.VkDescriptorSetLayout = undefined,
computeimagelayout: c.VkDescriptorSetLayout = undefined,

mesh_scenedata: [1]c.VkDescriptorSet = undefined,
vert_scenedata: [1]c.VkDescriptorSet = undefined,
combo: [1]c.VkDescriptorSet = undefined,
computeimage: [1]c.VkDescriptorSet = undefined,

const Self = @This();

pub fn create_shader_module(
    device: c.VkDevice,
    code: []const u8,
    alloc_callback: ?*c.VkAllocationCallbacks,
) ?c.VkShaderModule {
    std.debug.assert(code.len % 4 == 0);

    const data: *const u32 = @alignCast(@ptrCast(code.ptr));

    const shader_module_ci = std.mem.zeroInit(c.VkShaderModuleCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = data,
    });

    var shader_module: c.VkShaderModule = undefined;
    debug.check_vk_panic(c.VkCreateShaderModule(device, &shader_module_ci, alloc_callback, &shader_module));
    return shader_module;
}

pub const PipelineBuilder = struct {
    shader_stages: std.ArrayList(c.VkPipelineShaderStageCreateInfo),
    input_assembly: c.VkPipelineInputAssemblyStateCreateInfo,
    rasterizer: c.VkPipelineRasterizationStateCreateInfo,
    color_blend_attachment: c.VkPipelineColorBlendAttachmentState,
    multisample: c.VkPipelineMultisampleStateCreateInfo,
    pipeline_layout: c.VkPipelineLayout,
    depth_stencil: c.VkPipelineDepthStencilStateCreateInfo,
    render_info: c.VkPipelineRenderingCreateInfo,
    color_attachment_format: c.VkFormat,

    pub fn init(alloc: std.mem.Allocator) Self {
        var builder: Self = .{
            .shader_stages = std.ArrayList(c.VkPipelineShaderStageCreateInfo).init(alloc),
            .input_assembly = undefined,
            .rasterizer = undefined,
            .color_blend_attachment = undefined,
            .multisample = undefined,
            .pipeline_layout = undefined,
            .depth_stencil = undefined,
            .render_info = undefined,
            .color_attachment_format = c.VK_FORMAT_UNDEFINED,
        };
        builder.clear();
        return builder;
    }

    pub fn deinit(self: *Self) void {
        self.shader_stages.deinit();
    }

    fn clear(self: *Self) void {
        self.input_assembly = std.mem.zeroInit(c.VkPipelineInputAssemblyStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        });
        self.rasterizer = std.mem.zeroInit(c.VkPipelineRasterizationStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        });
        self.color_blend_attachment = std.mem.zeroInit(c.VkPipelineColorBlendAttachmentState, .{});
        self.multisample = std.mem.zeroInit(c.VkPipelineMultisampleStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        });
        self.depth_stencil = std.mem.zeroInit(c.VkPipelineDepthStencilStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        });
        self.render_info = std.mem.zeroInit(c.VkPipelineRenderingCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        });
        self.pipeline_layout = std.mem.zeroes(c.VkPipelineLayout);
        self.shader_stages.clearAndFree();
    }

    pub fn build_pipeline(self: *Self, device: c.VkDevice) c.VkPipeline {
        const viewport_state = std.mem.zeroInit(c.VkPipelineViewportStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        });

        const color_blending = std.mem.zeroInit(c.VkPipelineColorBlendStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .attachmentCount = 1,
            .pAttachments = &self.color_blend_attachment,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
        });

        const vertex_input_info = std.mem.zeroInit(c.VkPipelineVertexInputStateCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        });

        var pipeline_info = std.mem.zeroInit(c.VkGraphicsPipelineCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &self.render_info,
            .stageCount = @as(u32, @intCast(self.shader_stages.items.len)),
            .pStages = self.shader_stages.items.ptr,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &self.input_assembly,
            .pViewportState = &viewport_state,
            .pRasterizationState = &self.rasterizer,
            .pMultisampleState = &self.multisample,
            .pColorBlendState = &color_blending,
            .pDepthStencilState = &self.depth_stencil,
            .layout = self.pipeline_layout,
        });

        const dynamic_state = [_]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
        const dynamic_state_info : c.VkPipelineDynamicStateCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = dynamic_state.len,
            .pDynamicStates = &dynamic_state[0],
        };

        pipeline_info.pDynamicState = &dynamic_state_info;

        var pipeline: c.VkPipeline = undefined;
        if (c.vkCreateGraphicsPipelines(device, null, 1, &pipeline_info, null, &pipeline) == c.VK_SUCCESS) {
            return pipeline;
        } else {
            return null;
        }
    }

    pub fn set_shaders(self: *Self, vertex: c.VkShaderModule, fragment: c.VkShaderModule) void {
        self.shader_stages.clearAndFree();
        self.shader_stages.append(std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertex,
            .pName = "main",
        })) catch @panic("Failed to append vertex shader stage");
        self.shader_stages.append(std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragment,
            .pName = "main",
        })) catch @panic("Failed to append fragment shader stage");
    }

    pub fn set_input_topology(self: *Self, topology: c.VkPrimitiveTopology) void {
        self.input_assembly.topology = topology;
        self.input_assembly.primitiveRestartEnable = c.VK_FALSE;
    }

    pub fn set_polygon_mode(self: *Self, mode: c.VkPolygonMode) void {
        self.rasterizer.polygonMode = mode;
        self.rasterizer.lineWidth = 1.0;
    }

    pub fn set_cull_mode(self: *Self, mode: c.VkCullModeFlags, front_face: c.VkFrontFace) void {
        self.rasterizer.cullMode = mode;
        self.rasterizer.frontFace = front_face;
    }

    pub fn set_multisampling_none(self: *Self) void {
        self.multisample.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;
        self.multisample.sampleShadingEnable = c.VK_FALSE;
        self.multisample.minSampleShading = 1.0;
        self.multisample.pSampleMask = null;
        self.multisample.alphaToCoverageEnable = c.VK_FALSE;
        self.multisample.alphaToOneEnable = c.VK_FALSE;
    }

    pub fn disable_blending(self: *Self) void {
        self.color_blend_attachment.blendEnable = c.VK_FALSE;
        self.color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    }

    pub fn set_color_attachment_format(self: *Self, format: c.VkFormat) void {
        self.color_attachment_format = format;
        self.render_info.colorAttachmentCount = 1;
        self.render_info.pColorAttachmentFormats = &self.color_attachment_format;
    }

    pub fn set_depth_format(self: *Self, format: c.VkFormat) void {
        self.render_info.depthAttachmentFormat = format;
    }

    pub fn disable_depthtest(self: *Self) void {
        self.depth_stencil.depthTestEnable = c.VK_FALSE;
        self.depth_stencil.depthWriteEnable = c.VK_FALSE;
        self.depth_stencil.depthCompareOp = c.VK_COMPARE_OP_NEVER;
        self.depth_stencil.depthBoundsTestEnable = c.VK_FALSE;
        self.depth_stencil.stencilTestEnable = c.VK_FALSE;
        self.depth_stencil.minDepthBounds = 0.0;
        self.depth_stencil.maxDepthBounds = 1.0;
        self.depth_stencil.front = std.mem.zeroInit(c.VkStencilOpState, .{});
        self.depth_stencil.back = std.mem.zeroInit(c.VkStencilOpState, .{});
    }

    pub fn enable_depthtest(self: *Self, depthwrite_enable: bool, op: c.VkCompareOp) void {
        self.depth_stencil.depthTestEnable = c.VK_TRUE;
        self.depth_stencil.depthWriteEnable = if (depthwrite_enable) c.VK_TRUE else c.VK_FALSE;
        self.depth_stencil.depthCompareOp = op;
        self.depth_stencil.depthBoundsTestEnable = c.VK_FALSE;
        self.depth_stencil.stencilTestEnable = c.VK_FALSE;
        self.depth_stencil.minDepthBounds = 0.0;
        self.depth_stencil.maxDepthBounds = 1.0;
        self.depth_stencil.front = std.mem.zeroInit(c.VkStencilOpState, .{});
        self.depth_stencil.back = std.mem.zeroInit(c.VkStencilOpState, .{});
    }

    pub fn enable_blending_additive(self: *Self) void {
        self.color_blend_attachment.blendEnable = c.VK_TRUE;
        self.color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
        self.color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE;
        self.color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD;
        self.color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
        self.color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
        self.color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD;
        self.color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    }

    pub fn enable_blending_alpha(self: *Self) void {
        self.color_blend_attachment.blendEnable = c.VK_TRUE;
        self.color_blend_attachment.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
        self.color_blend_attachment.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        self.color_blend_attachment.colorBlendOp = c.VK_BLEND_OP_ADD;
        self.color_blend_attachment.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
        self.color_blend_attachment.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
        self.color_blend_attachment.alphaBlendOp = c.VK_BLEND_OP_ADD;
        self.color_blend_attachment.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    }
};

pub const DescriptorBuilder = struct {
    bindings: std.ArrayList(c.VkDescriptorSetLayoutBinding) = undefined,

    pub fn init(alloc: std.mem.Allocator) DescriptorBuilder {
        return .{ .bindings = .init(alloc) };
    }

    pub fn deinit(self: *DescriptorBuilder) void {
        self.bindings.deinit();
    }

    pub fn add_binding(self: *DescriptorBuilder, binding: u32, descriptor_type: c.VkDescriptorType) void {
        const new_binding: c.VkDescriptorSetLayoutBinding = .{
            .binding = binding,
            .descriptorType = descriptor_type,
            .descriptorCount = 1,
        };
        self.bindings.append(new_binding) catch @panic("Failed to append to bindings");
    }

    pub fn clear(self: *DescriptorBuilder) void {
        self.bindings.clearAndFree();
    }

    pub fn build(
        self: *DescriptorBuilder,
        device: c.VkDevice,
        shader_stages: c.VkShaderStageFlags,
        pnext: ?*anyopaque,
        flags: c.VkDescriptorSetLayoutCreateFlags,
    ) c.VkDescriptorSetLayout {
        for (self.bindings.items) |*binding| {
            binding.stageFlags |= shader_stages;
        }

        const info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = @as(u32, @intCast(self.bindings.items.len)),
            .pBindings = self.bindings.items.ptr,
            .flags = flags,
            .pNext = pnext,
        };
        var layout: c.VkDescriptorSetLayout = undefined;
        check_vk(c.vkCreateDescriptorSetLayout(device, &info, null, &layout)) catch {
            @panic("Failed to create descriptor set layout");
        };
        return layout;
    }
};

pub const Allocator = struct {
    pub const PoolSizeRatio = struct {
        ratio: f32,
        type: c.VkDescriptorType,
    };

    ready_pools: std.ArrayList(c.VkDescriptorPool) = undefined,
    full_pools: std.ArrayList(c.VkDescriptorPool) = undefined,
    ratios: std.ArrayList(PoolSizeRatio) = undefined,
    sets_per_pool: u32 = 0,

    pub fn init(
        self: *@This(),
        device: c.VkDevice,
        initial_sets: u32,
        pool_ratios: []PoolSizeRatio,
        alloc: std.mem.Allocator,
    ) void {
        self.ratios = .init(alloc);
        self.ratios.clearAndFree();
        self.ready_pools = .init(alloc);
        self.full_pools = .init(alloc);

        self.ratios.appendSlice(pool_ratios) catch @panic("Failed to append to ratios");
        const new_pool = create_pool(device, initial_sets, pool_ratios, std.heap.page_allocator);
        self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(initial_sets)) * 1.5);
        self.ready_pools.append(new_pool) catch @panic("Failed to append to ready_pools");
    }

    pub fn deinit(self: *@This(), device: c.VkDevice) void {
        self.clear_pools(device);
        self.destroy_pools(device);
        self.ready_pools.deinit();
        self.full_pools.deinit();
        self.ratios.deinit();
    }

    pub fn clear_pools(self: *@This(), device: c.VkDevice) void {
        for (self.ready_pools.items) |pool| {
            _ = c.vkResetDescriptorPool(device, pool, 0);
        }
        for (self.full_pools.items) |pool| {
            _ = c.vkResetDescriptorPool(device, pool, 0);
        }
        self.full_pools.clearAndFree();
    }

    pub fn destroy_pools(self: *@This(), device: c.VkDevice) void {
        for (self.ready_pools.items) |pool| {
            _ = c.vkDestroyDescriptorPool(device, pool, null);
        }
        self.ready_pools.clearAndFree();
        for (self.full_pools.items) |pool| {
            _ = c.vkDestroyDescriptorPool(device, pool, null);
        }
        self.full_pools.clearAndFree();
    }

    pub fn allocate(self: *@This(), device: c.VkDevice, layout: c.VkDescriptorSetLayout, pNext: ?*anyopaque) c.VkDescriptorSet {
        var pool_to_use = self.get_pool(device);

        var info = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = pNext,
            .descriptorPool = pool_to_use,
            .descriptorSetCount = 1,
            .pSetLayouts = &layout,
        };
        var descriptor_set: c.VkDescriptorSet = undefined;
        const result = c.vkAllocateDescriptorSets(device, &info, &descriptor_set);
        if (result == c.VK_ERROR_OUT_OF_POOL_MEMORY or result == c.VK_ERROR_FRAGMENTED_POOL) {
            self.full_pools.append(pool_to_use) catch @panic("Failed to append to full_pools");
            pool_to_use = self.get_pool(device);
            info.descriptorPool = pool_to_use;
            check_vk(c.vkAllocateDescriptorSets(device, &info, &descriptor_set)) catch {
                @panic("Failed to allocate descriptor set");
            };
        }
        self.ready_pools.append(pool_to_use) catch @panic("Failed to append to full_pools");
        return descriptor_set;
    }

    fn get_pool(self: *@This(), device: c.VkDevice) c.VkDescriptorPool {
        var new_pool: c.VkDescriptorPool = undefined;
        if (self.ready_pools.items.len != 0) {
            new_pool = self.ready_pools.pop().?;
        } else {
            new_pool = create_pool(device, self.sets_per_pool, self.ratios.items, std.heap.page_allocator);
            self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(self.sets_per_pool)) * 1.5);
            if (self.sets_per_pool > 4092) {
                self.sets_per_pool = 4092;
            }
        }
        return new_pool;
    }

    fn create_pool(
        device: c.VkDevice,
        set_count: u32,
        pool_ratios: []PoolSizeRatio,
        alloc: std.mem.Allocator,
    ) c.VkDescriptorPool {
        var pool_sizes: std.ArrayList(c.VkDescriptorPoolSize) = .init(alloc);
        defer pool_sizes.deinit();
        for (pool_ratios) |ratio| {
            const size = c.VkDescriptorPoolSize{
                .type = ratio.type,
                .descriptorCount = set_count * @as(u32, @intFromFloat(ratio.ratio)),
            };
            pool_sizes.append(size) catch @panic("Failed to append to pool_sizes");
        }

        const info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = 0,
            .maxSets = set_count,
            .poolSizeCount = @as(u32, @intCast(pool_sizes.items.len)),
            .pPoolSizes = pool_sizes.items.ptr,
        };

        var pool: c.VkDescriptorPool = undefined;
        check_vk(c.vkCreateDescriptorPool(device, &info, null, &pool)) catch @panic("Failed to create descriptor pool");
        return pool;
    }
};

// TODO dont know if i like this writer and its arraylists, need to allocate memory every time
pub const Writer = struct {
    writes: std.ArrayList(c.VkWriteDescriptorSet) = undefined,
    buffer_infos: std.ArrayList(c.VkDescriptorBufferInfo) = undefined,
    image_infos: std.ArrayList(c.VkDescriptorImageInfo) = undefined,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .writes = .init(allocator),
            .buffer_infos = .init(allocator),
            .image_infos = .init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.writes.deinit();
        self.buffer_infos.deinit();
        self.image_infos.deinit();
    }

    pub fn write_buffer(
        self: *@This(),
        binding: u32,
        buffer: c.VkBuffer,
        size: usize,
        offset: usize,
        ty: c.VkDescriptorType,
    ) void {
        const info_container = struct {
            var info: c.VkDescriptorBufferInfo = c.VkDescriptorBufferInfo{};
        };
        info_container.info = c.VkDescriptorBufferInfo{ .buffer = buffer, .offset = offset, .range = size };
        self.buffer_infos.append(info_container.info) catch @panic("failed to append");
        const write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = null,
            .descriptorCount = 1,
            .descriptorType = ty,
            .pBufferInfo = &info_container.info,
        };
        self.writes.append(write) catch @panic("failed to append");
    }

    pub fn write_image(
        self: *@This(),
        binding: u32,
        image: c.VkImageView,
        sampler: c.VkSampler,
        layout: c.VkImageLayout,
        ty: c.VkDescriptorType,
    ) void {
        const info_container = struct {
            var info: c.VkDescriptorImageInfo = c.VkDescriptorImageInfo{};
        };
        info_container.info = c.VkDescriptorImageInfo{ .sampler = sampler, .imageView = image, .imageLayout = layout };

        self.image_infos.append(info_container.info) catch @panic("append failed");
        const write = c.VkWriteDescriptorSet{
            .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = null,
            .descriptorCount = 1,
            .descriptorType = ty,
            .pImageInfo = &info_container.info,
        };
        self.writes.append(write) catch @panic("append failed");
    }

    pub fn clear(self: *@This()) void {
        self.writes.clearAndFree();
        self.buffer_infos.clearAndFree();
        self.image_infos.clearAndFree();
    }

    pub fn update_set(self: *@This(), device: c.VkDevice, set: c.VkDescriptorSet) void {
        for (self.writes.items) |*write| {
            write.*.dstSet = set;
        }
        c.vkUpdateDescriptorSets(device, @intCast(self.writes.items.len), self.writes.items.ptr, 0, null);
    }
};

pub fn init(core: *Core) void {
    _ = core;
}

pub fn deinit(core: *Core) void {
    _ = core;
}
